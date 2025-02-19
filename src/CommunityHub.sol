// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CommunityHub is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    
    // Referral system
    mapping(address => address) public referrers;
    mapping(address => uint256) public referralRewards;
    mapping(address => uint256) public referralCount;

    // Reputation system
    mapping(address => uint256) public userReputation;
    
    // Events
    event ReferralRegistered(address indexed referrer, address indexed referee);
    event RewardsDistributed(address indexed user, uint256 amount);
    event ReputationUpdated(address indexed user, uint256 newScore);

    constructor(address _token) Ownable(msg.sender) {
        token = IERC20(_token);
    }

    function registerReferral(address referrer) external {
        require(referrer != address(0), "Invalid referrer");
        require(referrer != msg.sender, "Cannot self refer");
        require(referrers[msg.sender] == address(0), "Already referred");

        referrers[msg.sender] = referrer;
        referralCount[referrer]++;
        
        // Initial reputation boost
        _updateReputation(referrer, 10);
        _updateReputation(msg.sender, 5);

        emit ReferralRegistered(referrer, msg.sender);
    }

    function distributeRewards(address user, uint256 amount) external  {
        address referrer = referrers[user];
        if (referrer != address(0)) {
            uint256 referralReward = amount * 5 / 100; // 5% referral reward
            referralRewards[referrer] += referralReward;
            token.safeTransfer(referrer, referralReward);
            emit RewardsDistributed(referrer, referralReward);
        }
    }

    function _updateReputation(address user, uint256 points) internal {
        userReputation[user] += points;
        emit ReputationUpdated(user, userReputation[user]);
    }

    // View functions
    function getReputation(address user) external view returns (uint256) {
        return userReputation[user];
    }

    function getReferralCount(address user) external view returns (uint256) {
        return referralCount[user];
    }
}