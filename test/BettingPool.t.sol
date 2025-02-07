// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BettingPool} from "../src/BettingPool.sol";
import {BetManager} from "../src/BetManager.sol";
import {IBettingPool} from "../src/interfaces/IBettingPool.sol";
import {MockOPToken} from "./mocks/MockOPToken.sol";
import {MockTournament} from "./mocks/MockTournament.sol";
import {MockCommunityHub} from "./mocks/MockCommunityHub.sol";

contract BettingPoolTest is Test {
    BettingPool public pool;
    BetManager public manager;
    MockOPToken public token;
    MockTournament public tournament;
    MockCommunityHub public communityHub;

    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public user3 = address(4);
    address public oracle = address(5);

    uint256 constant INITIAL_BALANCE = 10000 * 10**18;
    uint256 constant BET_AMOUNT = 5 * 10**18;

    event MatchCreated(uint256 indexed matchId, string name, uint256 startTime);
    event BetPlaced(uint256 indexed matchId, address indexed user, uint256 amount, uint8 prediction);
    event MatchFinalized(uint256 indexed matchId, uint8 winner);
    event WinningsClaimed(uint256 indexed matchId, address indexed user, uint256 amount);
    event ProtocolFeeUpdated(uint256 newFee);
    event TournamentSet(address indexed tournament);
    event CommunityHubSet(address indexed communityHub);

    function setUp() public {
        vm.startPrank(admin);
        // Deploy core contracts
        token = new MockOPToken();
        pool = new BettingPool(address(token));
        manager = new BetManager(address(pool));
        tournament = new MockTournament(address(pool));
        communityHub = new MockCommunityHub();

        // Setup integrations
        pool.setTournament(address(tournament));
        pool.setCommunityHub(address(communityHub));

        // Fund users
        token.transfer(user1, INITIAL_BALANCE);
        token.transfer(user2, INITIAL_BALANCE);
        token.transfer(user3, INITIAL_BALANCE);
        vm.stopPrank();
    }

    // Match Creation Tests
    function testMatchCreation() public {
        vm.startPrank(admin);
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 2 hours;

        vm.expectEmit(true, true, true, true);
        emit MatchCreated(1, "Test Match", startTime);
        pool.createMatch("Test Match", startTime, endTime, 1e18, 100e18);

        IBettingPool.Match memory match_ = pool.getMatch(1);
        assertEq(match_.name, "Test Match");
        assertEq(match_.startTime, startTime);
        assertEq(match_.endTime, endTime);
        assertEq(match_.minBet, 1e18);
        assertEq(match_.maxBet, 100e18);
        vm.stopPrank();
    }

    function testMatchCreationFailures() public {
        vm.startPrank(admin);
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 2 hours;

        // Empty name
        vm.expectRevert("Invalid name");
        pool.createMatch("", startTime, endTime, 1e18, 100e18);

        // Past start time
        vm.expectRevert("Invalid start time");
        pool.createMatch("Test Match", block.timestamp - 1, endTime, 1e18, 100e18);

        // End time before start time
        vm.expectRevert("Invalid end time");
        pool.createMatch("Test Match", startTime, startTime - 1, 1e18, 100e18);

        // Invalid bet limits
        vm.expectRevert("Invalid bet limits");
        pool.createMatch("Test Match", startTime, endTime, 0, 100e18);

        vm.expectRevert("Invalid bet limits");
        pool.createMatch("Test Match", startTime, endTime, 100e18, 1e18);
        vm.stopPrank();

        // Non-admin attempt
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        pool.createMatch("Test Match", startTime, endTime, 1e18, 100e18);
    }

    // Betting Tests
    function testSuccessfulBet() public {
        setupMatch();
        vm.startPrank(user1);
        token.approve(address(pool), BET_AMOUNT);
        
        vm.expectEmit(true, true, true, true);
        emit BetPlaced(1, user1, BET_AMOUNT, 1);
        pool.placeBet(1, BET_AMOUNT, 1);

        IBettingPool.Bet memory bet = pool.getUserBet(1, user1);
        assertEq(bet.amount, BET_AMOUNT);
        assertEq(bet.prediction, 1);
        assertEq(bet.claimed, false);
        vm.stopPrank();
    }

    function testBettingFailures() public {
        setupMatch();
        vm.startPrank(user1);
        token.approve(address(pool), BET_AMOUNT);

        // Non-existent match
        vm.expectRevert("Match does not exist");
        pool.placeBet(999, BET_AMOUNT, 1);

        // Invalid prediction
        vm.expectRevert("Invalid prediction");
        pool.placeBet(1, BET_AMOUNT, 0);
        vm.expectRevert("Invalid prediction");
        pool.placeBet(1, BET_AMOUNT, 3);

        // Bet too small/large
        vm.expectRevert("Bet too small");
        pool.placeBet(1, 0.5e18, 1);
        vm.expectRevert("Bet too large");
        pool.placeBet(1, 101e18, 1);

        // Place valid bet
        pool.placeBet(1, BET_AMOUNT, 1);

        // Double betting
        vm.expectRevert("Already bet on this match");
        pool.placeBet(1, BET_AMOUNT, 1);
        vm.stopPrank();
    }

    // Match Finalization Tests
    function testMatchFinalization() public {
        setupMatchWithBets();
        vm.warp(block.timestamp + 4 hours);

        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit MatchFinalized(1, 1);
        pool.finalizeMatch(1, 1);

        IBettingPool.Match memory match_ = pool.getMatch(1);
        assertTrue(match_.isFinalized);
        assertEq(match_.winner, 1);
        vm.stopPrank();
    }

    function testFinalizationFailures() public {
        setupMatchWithBets();

        // Before match end
        vm.prank(admin);
        vm.expectRevert("Match not ended");
        pool.finalizeMatch(1, 1);

        vm.warp(block.timestamp + 4 hours);
        
        // Non-admin finalization
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        pool.finalizeMatch(1, 1);

        // Invalid winner
        vm.prank(admin);
        vm.expectRevert("Invalid winner");
        pool.finalizeMatch(1, 3);

        // Finalize correctly
        vm.prank(admin);
        pool.finalizeMatch(1, 1);

        // Double finalization
        vm.prank(admin);
        vm.expectRevert("Match already finalized");
        pool.finalizeMatch(1, 1);
    }

    // Winnings Tests
    function testWinningsClaims() public {
        setupMatchWithBets();
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        pool.finalizeMatch(1, 1);

        vm.startPrank(user1);
        uint256 balanceBefore = token.balanceOf(user1);
        
        vm.expectEmit(true, true, true, true);
        emit WinningsClaimed(1, user1, calculateExpectedWinnings());
        pool.claimWinnings(1);
        
        uint256 balanceAfter = token.balanceOf(user1);
        uint256 winnings = balanceAfter - balanceBefore;
        
        assertTrue(winnings > 0);
        assertTrue(winnings < BET_AMOUNT * 2); // Account for fees
        vm.stopPrank();
    }

    function testClaimFailures() public {
        setupMatchWithBets();

        // Unfinalized match
        vm.prank(user1);
        vm.expectRevert("Match not finalized");
        pool.claimWinnings(1);

        // Finalize with different winner
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        pool.finalizeMatch(1, 2);

        // Losing bet claim
        vm.prank(user1);
        vm.expectRevert("Bet did not win");
        pool.claimWinnings(1);

        // No bet claim
        vm.prank(user3);
        vm.expectRevert("No bet placed");
        pool.claimWinnings(1);

        // Double claim
        vm.startPrank(user2);
        pool.claimWinnings(1);
        vm.expectRevert("Already claimed");
        pool.claimWinnings(1);
        vm.stopPrank();
    }

    // Integration Tests
    function testTournamentIntegration() public {
        setupMatch();

        // Tournament bet placement
        vm.prank(address(tournament));
        pool.placeTournamentBet(user1, 1, 1);

        IBettingPool.Bet memory bet = pool.getUserBet(1, user1);
        assertEq(bet.user, user1);
        assertEq(bet.prediction, 1);
        assertEq(bet.amount, 0);

        // Unauthorized tournament bet
        vm.prank(user1);
        vm.expectRevert("Only tournament");
        pool.placeTournamentBet(user1, 1, 1);
    }

    function testCommunityIntegration() public {
        setupMatchWithBets();

        // Verify activity tracking
        assertEq(communityHub.userActivity(user1), BET_AMOUNT);
        assertEq(communityHub.userActivity(user2), BET_AMOUNT);

        // Process winnings
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        pool.finalizeMatch(1, 1);

        vm.prank(user1);
        pool.claimWinnings(1);
        assertTrue(communityHub.userWinnings(user1) > 0);
    }

    // Admin Function Tests
    function testProtocolFeeManagement() public {
        vm.startPrank(admin);
        
        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeUpdated(500);
        pool.setProtocolFee(500);
        assertEq(pool.protocolFee(), 500);

        vm.expectRevert("Fee too high");
        pool.setProtocolFee(1001);

        vm.expectRevert("Fee too high");
        pool.setProtocolFee(type(uint256).max);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        pool.setProtocolFee(300);
    }

    function testPauseUnpause() public {
        // Test pause
        vm.prank(admin);
        pool.pause();
        assertTrue(pool.paused());

        // Test pause restrictions
        setupMatch();
        vm.startPrank(user1);
        token.approve(address(pool), BET_AMOUNT);
        vm.expectRevert("Pausable: paused");
        pool.placeBet(1, BET_AMOUNT, 1);
        vm.stopPrank();

        // Test unpause
        vm.prank(admin);
        pool.unpause();
        assertFalse(pool.paused());

        // Verify betting works after unpause
        vm.startPrank(user1);
        pool.placeBet(1, BET_AMOUNT, 1);
        vm.stopPrank();
    }

    // View Function Tests
    function testViewFunctions() public {
        setupMatchWithBets();

        // Test getMatch
        IBettingPool.Match memory match_ = pool.getMatch(1);
        assertEq(match_.id, 1);
        assertFalse(match_.isFinalized);

        // Test getUserBet
        IBettingPool.Bet memory bet = pool.getUserBet(1, user1);
        assertEq(bet.amount, BET_AMOUNT);
        assertEq(bet.prediction, 1);

        // Test getUserBetHistory
        uint256[] memory history = pool.getUserBetHistory(user1);
        assertEq(history.length, 1);
        assertEq(history[0], 1);

        // Test calculatePotentialWinnings
        uint256 potentialWinnings = pool.calculatePotentialWinnings(1, BET_AMOUNT, 1);
        assertTrue(potentialWinnings > 0);
    }

    // Helper Functions
    function setupMatch() internal {
        vm.prank(admin);
        pool.createMatch(
            "Test Match",
            block.timestamp + 1 hours,
            block.timestamp + 3 hours,
            1e18,
            100e18
        );
    }

    function setupMatchWithBets() internal {
        setupMatch();

        vm.startPrank(user1);
        token.approve(address(pool), BET_AMOUNT);
        pool.placeBet(1, BET_AMOUNT, 1);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(pool), BET_AMOUNT);
        pool.placeBet(1, BET_AMOUNT, 2);
        vm.stopPrank();
    }

    function calculateExpectedWinnings() internal view returns (uint256) {
        uint256 totalPool = BET_AMOUNT * 2;
        uint256 winnings = BET_AMOUNT * 2; // 1:1 odds with equal pools
        uint256 fee = (winnings * pool.protocolFee()) / 10000;
        return winnings - fee;
    }
}