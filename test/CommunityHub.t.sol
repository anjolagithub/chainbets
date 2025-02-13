// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CommunityHub} from "../src/CommunityHub.sol";
import {MockOPToken} from "./mocks/MockOPToken.sol";

contract CommunityHubTest is Test {
    CommunityHub public hub;
    MockOPToken public token;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    uint256 constant INITIAL_BALANCE = 1000000 * 10**18;
    uint256 constant LARGE_BALANCE = 10000000 * 10**18;

    function setUp() public {
        // Set owner to the test contract deployer
        owner = address(this);

        // Deploy token with large initial supply
        token = new MockOPToken();

        // Create addresses
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Mint tokens to addresses
        token.transfer(owner, LARGE_BALANCE);
        token.transfer(user1, INITIAL_BALANCE);
        token.transfer(user2, INITIAL_BALANCE);
        token.transfer(user3, INITIAL_BALANCE);

        // Deploy CommunityHub
        hub = new CommunityHub(address(token));

        // Transfer tokens to hub for rewards
        token.transfer(address(hub), LARGE_BALANCE);
    }

    function testReferralRegistration() public {
        vm.prank(user2);
        hub.registerReferral(user1);
        
        assertEq(hub.referrers(user2), user1);
        assertEq(hub.getReferralCount(user1), 1);
        assertEq(hub.getReputation(user1), 10);
        assertEq(hub.getReputation(user2), 5);
    }

    function testReferralRewards() public {
        testReferralRegistration();

        // Approve tokens for the hub
        token.approve(address(hub), LARGE_BALANCE);

        // Distribute rewards
        vm.startPrank(owner);
        token.transfer(address(hub), LARGE_BALANCE);
        hub.distributeRewards(user2, 100 * 10**18);
        vm.stopPrank();

        assertEq(hub.referralRewards(user1), 5 * 10**18);
    }

    function testMultipleReferrals() public {
        vm.prank(user2);
        hub.registerReferral(user1);

        vm.prank(user3);
        hub.registerReferral(user1);

        assertEq(hub.getReferralCount(user1), 2);
        assertEq(hub.getReputation(user1), 20);
    }

    function testReputationGrowth() public {
    vm.prank(user2);
    hub.registerReferral(user1);

    // Approve and transfer tokens to hub
    token.approve(address(hub), LARGE_BALANCE);
    token.transfer(address(hub), LARGE_BALANCE);

    // Initial reputation check
    uint256 initialReputation = hub.getReputation(user1);
    assertEq(initialReputation, 10, "Initial reputation should be 10");

    // Distribute rewards as owner
    vm.startPrank(owner);
    for(uint i = 0; i < 5; i++) {
        hub.distributeRewards(user2, 10 * 10**18);
    }
    vm.stopPrank();

    // Get new reputation
    uint256 newReputation = hub.getReputation(user1);

    // Assert that reputation remains the same
    assertEq(newReputation, initialReputation, "Reputation should not change");
    }
}