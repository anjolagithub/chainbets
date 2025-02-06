// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BettingPool} from "../src/BettingPool.sol";
import {BetManager} from "../src/BetManager.sol";
import {IBettingPool} from "../src/interfaces/IBettingPool.sol";
import {MockOPToken} from "./mocks/MockOPToken.sol";

contract BettingPoolTest is Test {
    BettingPool public pool;
    BetManager public manager;
    MockOPToken public token;

    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public oracle = address(4);

    uint256 constant INITIAL_BALANCE = 10000 * 10**18;
    uint256 constant BET_AMOUNT = 5 * 10**18;

    function setUp() public {
        // Deploy mock token
        vm.startPrank(admin);
        token = new MockOPToken();

        // Deploy core contracts
        pool = new BettingPool(address(token));
        manager = new BetManager(address(pool));

        // Setup users with tokens
        token.transfer(user1, INITIAL_BALANCE);
        token.transfer(user2, INITIAL_BALANCE);
        vm.stopPrank();
    }

    function testMatchCreation() public {
        vm.startPrank(admin);
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 2 hours;

        pool.createMatch("Test Match", startTime, endTime, 1e18, 100e18);

        IBettingPool.Match memory match_ = pool.getMatch(1);
        assertEq(match_.name, "Test Match");
        assertEq(match_.startTime, startTime);
        assertEq(match_.endTime, endTime);
        vm.stopPrank();
    }

    function testBetPlacement() public {
        // Setup match
        vm.startPrank(admin);
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 2 hours;
        pool.createMatch("Test Match", startTime, endTime, 1e18, 100e18);
        vm.stopPrank();

        // Place bet
        vm.startPrank(user1);
        token.approve(address(pool), BET_AMOUNT);
        pool.placeBet(1, BET_AMOUNT, 1); // Bet on team A

        IBettingPool.Bet memory bet = pool.getUserBet(1, user1);
        assertEq(bet.amount, BET_AMOUNT);
        assertEq(bet.prediction, 1);
        vm.stopPrank();
    }

    function testMatchFinalization() public {
        // Setup match and bets
        setupMatchWithBets();

        // Advance time past match end
        vm.warp(block.timestamp + 4 hours);

        // Finalize match
        vm.prank(admin);
        pool.finalizeMatch(1, 1); // Team A wins

        IBettingPool.Match memory match_ = pool.getMatch(1);
        assertTrue(match_.isFinalized);
        assertEq(match_.winner, 1);
    }

    function testWinningsClaim() public {
        // Setup match and bets
        setupMatchWithBets();

        // Advance time and finalize
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        pool.finalizeMatch(1, 1); // Team A wins

        // Claim winnings
        vm.startPrank(user1);
        uint256 balanceBefore = token.balanceOf(user1);
        pool.claimWinnings(1);
        uint256 balanceAfter = token.balanceOf(user1);

        assertTrue(balanceAfter > balanceBefore);
        vm.stopPrank();
    }

    function testEmergencyPause() public {
        vm.startPrank(admin);
        // Setup match first
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 2 hours;
        pool.createMatch("Test Match", startTime, endTime, 1e18, 100e18);
        pool.pause();
        vm.stopPrank();

        // Try to place bet while paused
        vm.startPrank(user1);
        token.approve(address(pool), BET_AMOUNT);
        vm.expectRevert();  // Just expect any revert
        pool.placeBet(1, BET_AMOUNT, 1);
        vm.stopPrank();
    }

    function testProtocolFee() public {
        // Setup match and bets
        setupMatchWithBets();

        // Change protocol fee
        vm.prank(admin);
        pool.setProtocolFee(500); // 5%

        // Advance time and finalize
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        pool.finalizeMatch(1, 1);

        // Claim and verify winnings with new fee
        vm.startPrank(user1);
        uint256 balanceBefore = token.balanceOf(user1);
        pool.claimWinnings(1);
        uint256 balanceAfter = token.balanceOf(user1);

        uint256 actualWinnings = balanceAfter - balanceBefore;
        assertTrue(actualWinnings > 0);
        assertTrue(actualWinnings < BET_AMOUNT * 2); // Should be less than 2x due to fee
        vm.stopPrank();
    }

    // Helper function to setup a match with bets
    function setupMatchWithBets() internal {
        // Create match
        vm.startPrank(admin);
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 2 hours;
        pool.createMatch("Test Match", startTime, endTime, 1e18, 100e18);
        vm.stopPrank();

        // Place bet from user1
        vm.startPrank(user1);
        token.approve(address(pool), BET_AMOUNT);
        pool.placeBet(1, BET_AMOUNT, 1); // Bet on team A
        vm.stopPrank();

        // Place bet from user2
        vm.startPrank(user2);
        token.approve(address(pool), BET_AMOUNT);
        pool.placeBet(1, BET_AMOUNT, 2); // Bet on team B
        vm.stopPrank();
    }
}