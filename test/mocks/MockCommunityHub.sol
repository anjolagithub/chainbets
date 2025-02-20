// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockCommunityHub {
    mapping(address => uint256) public userActivity;
    mapping(address => uint256) public userWinnings;

    function updateUserActivity(address user, uint256 amount) external {
        userActivity[user] += amount;
    }

    function processWinnings(address user, uint256 amount) external {
        userWinnings[user] += amount;
    }
}
