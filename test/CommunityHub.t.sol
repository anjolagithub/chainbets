// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CommunityHub} from "../src/CommunityHub.sol";
import {MockOPToken} from "./mocks/MockOPToken.sol";

contract CommunityHubTest is Test {
    CommunityHub public hub;
    MockOPToken public token;

    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public user3 = address(4);

    uint256 constant INITIAL_BALANCE = 1000 * 10**18;

    function setUp() public {
        vm.startPrank(admin);
        token = new MockOPToken();
        hub = new CommunityHub(address(token));
        
        token.transfer(admin, INITIAL_BALANCE);
        token.transfer(user1, INITIAL_BALANCE);
        token.transfer(user2, INITIAL_BALANCE);
        vm.stopPrank();
    }

    function testReferralRegistration() public {
        vm.startPrank(user2);
        hub.registerReferral(user1);
        
        assertEq(hub.referrers(user2), user1);
        assertEq(hub.getReferralCount(user1), 1);
        assertEq(hub.getReputation(user1), 10); // Referrer bonus
        assertEq(hub.getReputation(user2), 5);  // Referee bonus
        vm.stopPrank();
    }

    function testReferralRewards() public {
        // Setup referral
        testReferralRegistration();

        // Simulate reward distribution
        vm.startPrank(admin);
        token.approve(address(hub), 100 * 10**18);
        hub.distributeRewards(user2, 100 * 10**18);
        vm.stopPrank();

        // Check rewards
        uint256 referralReward = hub.referralRewards(user1);
        assertEq(referralReward, 5 * 10**18); // 5% of 100 tokens
    }

    function testMultipleReferrals() public {
        vm.startPrank(user2);
        hub.registerReferral(user1);
        vm.stopPrank();

        vm.startPrank(user3);
        hub.registerReferral(user1);
        vm.stopPrank();

        assertEq(hub.getReferralCount(user1), 2);
        assertEq(hub.getReputation(user1), 20); // 10 points per referral
    }

    function testReputationGrowth() public {
        vm.startPrank(user2);
        hub.registerReferral(user1);
        vm.stopPrank();

        vm.startPrank(admin);
        // Simulate multiple reward distributions
        for(uint i = 0; i < 5; i++) {
            hub.distributeRewards(user2, 10 * 10**18);
        }
        vm.stopPrank();

        assertTrue(hub.getReputation(user1) > 10); // Should have grown beyond initial bonus
    }
}