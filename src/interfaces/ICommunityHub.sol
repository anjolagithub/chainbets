// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICommunityHub {
    struct Proposal {
        uint256 id;
        string description;
        uint256 matchId;
        uint256 proposedOdds;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        bool executed;
        address proposer;
    }

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ReferralRegistered(address indexed referrer, address indexed referee);
    event RewardsClaimed(address indexed user, uint256 amount);

    function createProposal(string memory description, uint256 matchId, uint256 proposedOdds) external;
    function vote(uint256 proposalId, bool support) external;
    function registerReferral(address referrer) external;
    function claimReferralRewards() external;
}
