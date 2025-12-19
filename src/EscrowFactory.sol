// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Escrow} from "./Escrow.sol";

contract EscrowFactory {
    // ===== Events =====
    event EscrowCreated(
        address indexed escrow,
        address indexed depositor,
        address indexed beneficiary,
        address token,
        uint256 amount,
        uint256 deadline
    );

    // ===== Errors =====
    error EscrowFactory__InvalidSafe();
    error EscrowFactory__InvalidOracle();
    error EscrowFactory__InvalidBeneficiary();
    error EscrowFactory__InvalidAmount();
    error EscrowFactory__InvalidDeadline();

    // ===== State Variables =====
    address public immutable i_arbitratorSafe;
    address public immutable i_oracle;

    // ===== Functions =====
    constructor(address _arbitratorSafe, address _oracle) {
        if (_arbitratorSafe == address(0)) {
            revert EscrowFactory__InvalidSafe();
        }
        if (_oracle == address(0)) {
            revert EscrowFactory__InvalidOracle();
        }

        i_arbitratorSafe = _arbitratorSafe;
        i_oracle = _oracle;
    }

    // External Functions
    function createEscrow(address beneficiary, address token, uint256 amount, uint256 deadline)
        external
        returns (address escrow)
    {
        if (beneficiary == address(0)) {
            revert EscrowFactory__InvalidBeneficiary();
        }
        if (amount == 0) {
            revert EscrowFactory__InvalidAmount();
        }
        if (deadline <= block.timestamp) {
            revert EscrowFactory__InvalidDeadline();
        }

        escrow = address(new Escrow(msg.sender, beneficiary, token, amount, deadline, i_arbitratorSafe, i_oracle));

        emit EscrowCreated(escrow, msg.sender, beneficiary, token, amount, deadline);
    }
}
