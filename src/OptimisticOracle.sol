// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract OptimisticOracle {
    // ===== Type Declarations =====
    enum Outcome {
        NONE,
        RELEASE,
        REFUND
    }

    struct Proposal {
        address proposer;
        Outcome outcome;
        uint256 timestamp;
        bool disputed;
        bool resolved;
    }

    // ===== State Variables =====
    uint256 public constant CHALLENGE_PERIOD = 2 days;
    address public immutable i_resolver;

    mapping(bytes32 => Proposal) public proposals;

    // ===== Events =====
    event Proposed(bytes32 indexed id, Outcome outcome);
    event Disputed(bytes32 indexed id);
    event Resolved(bytes32 indexed id, Outcome outcome);

    // ===== Errors =====
    error OptimisticOracle__NotResolver();
    error OptimisticOracle__AlreadyProposed();
    error OptimisticOracle__InvalidOutcome();
    error OptimisticOracle__NoProposalExist();
    error OptimisticOracle__AlreadyDisputed();
    error OptimisticOracle__ChallengeWindowClosed();
    error OptimisticOracle__AlreadyResolved();
    error OptimisticOracle__Disputed();
    error OptimisticOracle__ChallengeWindowNotClosed();
    error OptimisticOracle__NotDisputed();

    // ===== Modifiers =====
    modifier onlyResolver() {
        if (msg.sender != i_resolver) {
            revert OptimisticOracle__NotResolver();
        }
        _;
    }

    // ===== Functions =====

    // ===== Constructor =====
    constructor(address _resolver) {
        i_resolver = _resolver;
    }

    // ===== External Functions =====
    function propose(bytes32 id, Outcome outcome) external {
        if (proposals[id].timestamp == 0) {
            revert OptimisticOracle__AlreadyProposed();
        }
        if (outcome == Outcome.NONE) {
            revert OptimisticOracle__InvalidOutcome();
        }

        proposals[id] = Proposal({
            proposer: msg.sender, outcome: outcome, timestamp: block.timestamp, disputed: false, resolved: false
        });

        emit Proposed(id, outcome);
    }

    function dispute(bytes32 id) external {
        Proposal storage p = proposals[id];
        if (p.timestamp == 0) {
            revert OptimisticOracle__NoProposalExist();
        }
        if (p.disputed) {
            revert OptimisticOracle__AlreadyDisputed();
        }
        if (block.timestamp >= p.timestamp + CHALLENGE_PERIOD) {
            revert OptimisticOracle__ChallengeWindowClosed();
        }

        p.disputed = true;
        emit Disputed(id);
    }

    function finalize(bytes32 id) external returns (Outcome) {
        Proposal storage p = proposals[id];
        if (p.timestamp == 0) {
            revert OptimisticOracle__NoProposalExist();
        }
        if (p.resolved) {
            revert OptimisticOracle__AlreadyResolved();
        }
        if (p.disputed) {
            revert OptimisticOracle__Disputed();
        }
        if (block.timestamp < p.timestamp + CHALLENGE_PERIOD) {
            revert OptimisticOracle__ChallengeWindowNotClosed();
        }

        p.resolved = true;
        emit Resolved(id, p.outcome);

        return p.outcome;
    }

    function resolveDispute(bytes32 id, Outcome finalOutcome) external onlyResolver returns (Outcome) {
        Proposal storage p = proposals[id];
        if (!p.disputed) {
            revert OptimisticOracle__NotDisputed();
        }
        if (p.resolved) {
            revert OptimisticOracle__AlreadyResolved();
        }

        p.resolved = true;
        p.outcome = finalOutcome;

        emit Resolved(id, finalOutcome);

        return finalOutcome;
    }
}
