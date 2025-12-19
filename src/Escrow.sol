// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Escrow is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // ===== Type Declarations =====
    enum State {
        CREATED,
        FUNDED,
        DISPUTED,
        RELEASED,
        REFUNDED,
        RESOLVED
    }

    // ===== State Variables =====
    address public immutable i_depositor;
    address public immutable i_beneficiary;
    address public immutable i_arbitratorSafe;
    address public immutable i_oracle;

    address public immutable i_token; // address(0) = ETH
    uint256 public immutable i_amount;
    uint256 public immutable i_deadline;

    State public state;

    mapping(bytes32 => bool) public usedOracleMessages;

    // ===== Events =====
    event Funded(address indexed from);
    event Disputed(address indexed by);
    event Released(address indexed to);
    event Refunded(address indexed to);
    event Resolved(address indexed executor, bool toBeneficiary);
    event OracleResolved(bool toBeneficiary, uint256 nonce);

    // ===== Errors =====
    error Escrow__NotParticipant();
    error Escrow__NotArbitratorSafe();
    error Escrow__NotDepositor();
    error Escrow__InvalidState();
    error Escrow__NotExactETHAmount();
    error Escrow__EthTransferFailed();
    error Escrow__DeadlineExpired();
    error Escrow__DeadlineNotExpired();
    error Escrow__NotBeneficiary();
    error Escrow__OracleReplay();
    error Escrow__BadOracleSignature();

    // ===== Modifiers =====
    modifier onlyParticipants() {
        if (msg.sender != i_depositor || msg.sender != i_beneficiary) {
            revert Escrow__NotParticipant();
        }
        _;
    }

    modifier onlyArbitrator() {
        if (msg.sender != i_arbitratorSafe) {
            revert Escrow__NotArbitratorSafe();
        }
        _;
    }

    modifier onlyDepositor() {
        if (msg.sender != i_depositor) {
            revert Escrow__NotDepositor();
        }
        _;
    }

    modifier onlyBeneficiary() {
        if (msg.sender != i_beneficiary) {
            revert Escrow__NotBeneficiary();
        }
        _;
    }

    // ===== Functions =====
    constructor(
        address _depositor,
        address _beneficiary,
        address _token,
        uint256 _amount,
        uint256 _deadline,
        address _arbitratorSafe,
        address _oracle
    ) {
        i_depositor = _depositor;
        i_beneficiary = _beneficiary;
        i_token = _token;
        i_amount = _amount;
        i_deadline = _deadline;
        i_arbitratorSafe = _arbitratorSafe;
        i_oracle = _oracle;

        state = State.CREATED;
    }

    // ===== External Functions =====
    function fund() external payable nonReentrant {
        if (state != State.CREATED) {
            revert Escrow__InvalidState();
        }

        if (i_token == address(0)) {
            if (msg.value != i_amount) {
                revert Escrow__NotExactETHAmount();
            }
        } else {
            IERC20(i_token).safeTransferFrom(msg.sender, address(this), i_amount);
        }

        state = State.FUNDED;
        emit Funded(msg.sender);
    }

    function release() external onlyDepositor nonReentrant {
        if (state != State.FUNDED) {
            revert Escrow__InvalidState();
        }
        if (block.timestamp > i_deadline) {
            revert Escrow__DeadlineExpired();
        }

        _payout(i_beneficiary);
        state = State.RELEASED;
        emit Released(i_beneficiary);
    }

    function refund() external onlyBeneficiary nonReentrant {
        if (state != State.FUNDED) {
            revert Escrow__InvalidState();
        }
        if (block.timestamp <= i_deadline) {
            revert Escrow__DeadlineNotExpired();
        }

        _payout(i_depositor);
        state = State.REFUNDED;
        emit Refunded(i_depositor);
    }

    function dispute() external onlyParticipants {
        if (state != State.FUNDED) {
            revert Escrow__InvalidState();
        }

        state = State.DISPUTED;
        emit Disputed(msg.sender);
    }

    function resolve(bool releaseToBeneficiary) external onlyArbitrator nonReentrant {
        if (state != State.DISPUTED) {
            revert Escrow__InvalidState();
        }

        _payout(releaseToBeneficiary ? i_beneficiary : i_depositor);
        state = State.RESOLVED;

        emit Resolved(msg.sender, releaseToBeneficiary);
    }

    function oracleResolve(bool releaseToBeneficiary, uint256 nonce, bytes calldata signature) external nonReentrant {
        if (state != State.FUNDED || state != State.DISPUTED) {
            revert Escrow__InvalidState();
        }

        bytes32 messageHash = keccak256(abi.encodePacked(address(this), releaseToBeneficiary, nonce));

        if (usedOracleMessages[messageHash]) {
            revert Escrow__OracleReplay();
        }

        address signer = messageHash.recover(signature);
        if (signer != i_oracle) {
            revert Escrow__BadOracleSignature();
        }

        usedOracleMessages[messageHash] = true;

        _payout(releaseToBeneficiary ? i_beneficiary : i_depositor);
        state = State.RELEASED;

        emit OracleResolved(releaseToBeneficiary, nonce);
    }

    // ===== Internal Functions =====
    function _payout(address to) internal {
        if (i_token == address(0)) {
            (bool success,) = payable(to).call{value: i_amount}("");
            if (!success) {
                revert Escrow__EthTransferFailed();
            }
        } else {
            IERC20(i_token).safeTransfer(to, i_amount);
        }
    }
}
