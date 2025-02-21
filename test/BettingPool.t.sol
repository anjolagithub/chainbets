// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BettingPool} from "../src/BettingPool.sol";
import {BetManager} from "../src/BetManager.sol";
import {IBettingPool} from "../src/interfaces/IBettingPool.sol";
import {MockOPToken} from "./mocks/MockOPToken.sol";
import {MockTournament} from "./mocks/MockTournament.sol";
import {MockCommunityHub} from "./mocks/MockCommunityHub.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import "forge-std/console2.sol"; // Correct import statement


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

    uint256 constant INITIAL_BALANCE = 10000 * 10 ** 18;
    uint256 constant BET_AMOUNT = 5 * 10 ** 18;

    event MatchCreated(uint256 indexed matchId, string name, uint256 startTime);
    event BetPlaced(uint256 indexed matchId, address indexed user, uint256 amount, uint8 prediction);
    event MatchFinalized(uint256 indexed matchId, uint8 winner);
    event WinningsClaimed(uint256 indexed matchId, address indexed user, uint256 amount);
    event ProtocolFeeUpdated(uint256 newFee);
    event TournamentSet(address indexed tournament);
    event CommunityHubSet(address indexed communityHub);
    event EmergencyWithdraw(address token, uint256 amount);

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

        // Transfer tokens to users
        token.transfer(user1, INITIAL_BALANCE);
        token.transfer(user2, INITIAL_BALANCE);
        token.transfer(user3, INITIAL_BALANCE);
        vm.stopPrank();
    }

    function testMatchCreation() public {
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 2 hours;

        vm.expectEmit(true, true, true, true);
        emit MatchCreated(1, "Test Match", startTime);
        pool.createMatch("Test Match", startTime, endTime, 1e18, 100e18);

        IBettingPool.Match memory match_ = pool.getMatch(1);
        assertEq(match_.id, 1);
        assertEq(match_.name, "Test Match");
        assertEq(match_.startTime, startTime);
        assertEq(match_.endTime, endTime);
        assertEq(match_.minBet, 1e18);
        assertEq(match_.maxBet, 100e18);
    }

    function testMatchCreationFailures() public {
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 2 hours;

        vm.expectRevert("Invalid name");
        pool.createMatch("", startTime, endTime, 1e18, 100e18);

        vm.expectRevert("Invalid start time");
        pool.createMatch("Test Match", block.timestamp - 1, endTime, 1e18, 100e18);

        vm.expectRevert("Invalid end time");
        pool.createMatch("Test Match", startTime, startTime - 1, 1e18, 100e18);

        vm.expectRevert("Invalid bet limits");
        pool.createMatch("Test Match", startTime, endTime, 0, 100e18);

        vm.expectRevert("Invalid bet limits");
        pool.createMatch("Test Match", startTime, endTime, 100e18, 1e18);
    }

    function testProtocolFeeManagement() public {
        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeUpdated(500);
        pool.setProtocolFee(500);
        assertEq(pool.protocolFee(), 500);

        vm.expectRevert("Fee too high");
        pool.setProtocolFee(1001);
        vm.stopPrank();

        // Non-admin attempt
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(user1)));
        vm.prank(user1);
        pool.setProtocolFee(300);
    }

    function testIntegrationManagement() public {
        vm.startPrank(admin);
        address newTournament = address(6);
        address newCommunityHub = address(7);

        vm.expectEmit(true, true, true, true);
        emit TournamentSet(newTournament);
        pool.setTournament(newTournament);
        assertEq(address(pool.tournament()), newTournament);

        vm.expectEmit(true, true, true, true);
        emit CommunityHubSet(newCommunityHub);
        pool.setCommunityHub(newCommunityHub);
        assertEq(address(pool.communityHub()), newCommunityHub);

        vm.expectRevert("Invalid tournament address");
        pool.setTournament(address(0));

        vm.expectRevert("Invalid community hub address");
        pool.setCommunityHub(address(0));
        vm.stopPrank();

        // Non-admin attempts
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(user1)));
        pool.setTournament(newTournament);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(user1)));
        pool.setCommunityHub(newCommunityHub);
        vm.stopPrank();
    }

    function testPauseUnpause() public {
        // Test pause by admin
        vm.prank(admin);
        pool.pause();
        assertTrue(pool.paused());

        // Setup match before testing pause
        setupMatch();

        // Test pause restrictions
        vm.startPrank(user1);
        token.approve(address(pool), BET_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
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

    function testBettingSystem() public {
        setupMatch();

        // Test bet placement
        vm.startPrank(user1);
        token.approve(address(pool), BET_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit BetPlaced(1, user1, BET_AMOUNT, 1);
        pool.placeBet(1, BET_AMOUNT, 1);

        IBettingPool.Bet memory bet = pool.getUserBet(1, user1);
        assertEq(bet.amount, BET_AMOUNT);
        assertEq(bet.prediction, 1);
        vm.stopPrank();

        // Test bet failures
        vm.startPrank(user2);
        vm.expectRevert("Match does not exist");
        pool.placeBet(2, BET_AMOUNT, 1);

        token.approve(address(pool), BET_AMOUNT);
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert("Match already started");
        pool.placeBet(1, BET_AMOUNT, 1);
        vm.stopPrank();
    }

    function testFinalizationFailures() public {
        setupMatchWithBets();

        // Before match end
        vm.expectRevert("Match not ended");
        pool.finalizeMatch(1, 1);

        vm.warp(block.timestamp + 4 hours);

        // Invalid winner
        vm.expectRevert("Invalid winner");
        pool.finalizeMatch(1, 3);

        // Finalize correctly
        pool.finalizeMatch(1, 1);

        // Double finalization
        vm.expectRevert("Match already finalized");
        pool.finalizeMatch(1, 1);
    }

    function testWinningsClaims() public {
        setupMatchWithBets();
        vm.warp(block.timestamp + 4 hours);

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
        pool.finalizeMatch(1, 1);

        vm.prank(user1);
        pool.claimWinnings(1);
        assertTrue(communityHub.userWinnings(user1) > 0);
    }

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

    function testEmergencyWithdraw() public {
        // Send some tokens to the contract
        vm.startPrank(user1);
        token.transfer(address(pool), BET_AMOUNT);
        vm.stopPrank();

        // Test emergency withdraw by non-admin
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(user1)));
        pool.emergencyWithdraw(address(token));

        // Test emergency withdraw by admin
        vm.startPrank(admin);
        uint256 balanceBefore = token.balanceOf(admin);

        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(address(token), BET_AMOUNT);
        pool.emergencyWithdraw(address(token));

        uint256 balanceAfter = token.balanceOf(admin);
        assertEq(balanceAfter - balanceBefore, BET_AMOUNT);

        // Test withdraw with no balance
        vm.expectRevert("No balance to withdraw");
        pool.emergencyWithdraw(address(token));

        // Test withdraw with invalid token
        vm.expectRevert("Invalid token");
        pool.emergencyWithdraw(address(0));
        vm.stopPrank();
    }

    // Helper Functions
    function setupMatch() internal {
        pool.createMatch("Test Match", block.timestamp + 1 hours, block.timestamp + 3 hours, 1e18, 100e18);
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
        uint256 winnings = BET_AMOUNT * 2; // 1:1 odds with equal pools
        uint256 fee = (winnings * pool.protocolFee()) / 10000;
        return winnings - fee;
    }

    function testPlaceBetMissingRevertData() public {
        setupMatch();

        // Simulate a failing scenario
        uint256 matchId = 1;
        uint256 amount = 0.5 ether; // Bet amount below minBet
        uint8 prediction = 1;

        // Expect the transaction to revert without a message
        vm.expectRevert();
        vm.prank(user1);
        pool.placeBet(matchId, amount, prediction);
    }

    function testPlaceBetSuccess() public {
        setupMatch();

        // Test bet placement
        vm.startPrank(user1);
        token.approve(address(pool), BET_AMOUNT);

        console2.log("User balance before bet:", token.balanceOf(user1));
        console2.log("User allowance before bet:", token.allowance(user1, address(pool)));

        vm.expectEmit(true, true, true, true);
        emit BetPlaced(1, user1, BET_AMOUNT, 1);
        pool.placeBet(1, BET_AMOUNT, 1);

        IBettingPool.Bet memory bet = pool.getUserBet(1, user1);
        assertEq(bet.amount, BET_AMOUNT);
        assertEq(bet.prediction, 1);

        console2.log("User balance after bet:", token.balanceOf(user1));
        console2.log("User allowance after bet:", token.allowance(user1, address(pool)));

        vm.stopPrank();
    }
}
