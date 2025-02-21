// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Tournament} from "../src/Tournament.sol";
import {BettingPool} from "../src/BettingPool.sol";
import {MockOPToken} from "./mocks/MockOPToken.sol";
import {ITournament} from "../src/interfaces/ITournament.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TournamentTest is Test {
    Tournament public tournament;
    BettingPool public pool;
    MockOPToken public token;

    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    uint256 constant INITIAL_BALANCE = 10000 * 10 ** 18;
    uint256 constant ENTRY_FEE = 10 * 10 ** 18;

    event TournamentCreated(uint256 indexed id, string name, uint256 startTime);
    event PlayerJoined(uint256 indexed tournamentId, address indexed player);
    event PredictionSubmitted(uint256 indexed tournamentId, uint256 indexed matchId, address indexed player);

    function setUp() public {
        vm.startPrank(admin);
        // Deploy contracts
        token = new MockOPToken();
        pool = new BettingPool(address(token));
        tournament = new Tournament(address(pool), address(token));

        // Setup pool
        pool.setTournament(address(tournament));

        // Transfer tokens to users
        token.transfer(user1, INITIAL_BALANCE);
        token.transfer(user2, INITIAL_BALANCE);

        // Create matches for testing
        pool.createMatch(
            "Test Match 1",
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            1e18, // minBet
            100e18 // maxBet
        );
        pool.createMatch(
            "Test Match 2",
            block.timestamp + 2 hours,
            block.timestamp + 3 hours,
            1e18, // minBet
            100e18 // maxBet
        );

        vm.stopPrank();
    }

    function testTournamentCreation() public {
        uint256[] memory matchIds = new uint256[](2);
        matchIds[0] = 1;
        matchIds[1] = 2;

        vm.startPrank(admin);

        // Test event emission
        vm.expectEmit(true, true, true, true);
        emit TournamentCreated(0, "Test Tournament", block.timestamp + 1 hours);

        tournament.createTournament(
            "Test Tournament", block.timestamp + 1 hours, block.timestamp + 3 hours, ENTRY_FEE, matchIds
        );

        // Verify tournament creation
        assertEq(tournament.nextTournamentId(), 1);
        vm.stopPrank();
    }

    function testTournamentJoining() public {
        // Setup tournament
        testTournamentCreation();

        vm.startPrank(user1);
        token.approve(address(tournament), ENTRY_FEE);

        vm.expectEmit(true, true, true, true);
        emit PlayerJoined(0, user1);

        tournament.joinTournament(0);
        assertTrue(tournament.participants(0, user1));
        vm.stopPrank();
    }

    function testPredictionSubmission() public {
        // Setup tournament and match
        testTournamentCreation();

        // Join and predict
        vm.startPrank(user1);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.joinTournament(0);

        vm.expectEmit(true, true, true, true);
        emit PredictionSubmitted(0, 1, user1);

        tournament.submitPrediction(0, 1, 1); // Predict team A wins
        assertEq(tournament.predictions(0, user1, 1), 1);
        vm.stopPrank();
    }

    function testRewardClaiming() public {
        // Setup tournament and predictions
        testPredictionSubmission();

        // Advance time and finalize match
        vm.warp(block.timestamp + 3 hours);

        vm.startPrank(admin);
        pool.finalizeMatch(1, 1); // Team A wins

        // Advance time to ensure tournament has ended
        vm.warp(block.timestamp + 24 hours);

        // Update scores
        address[] memory players = new address[](1);
        players[0] = user1;
        uint256[] memory matchScores = new uint256[](1);
        matchScores[0] = 10;
        tournament.updateScores(0, 1, players, matchScores);
        vm.stopPrank();

        // Claim rewards
        vm.startPrank(user1);
        uint256 balanceBefore = token.balanceOf(user1);
        tournament.claimTournamentRewards(0);
        uint256 balanceAfter = token.balanceOf(user1);
        assertTrue(balanceAfter > balanceBefore);
        vm.stopPrank();
    }

    // Instead of one large test, split into specific revert cases
    function test_RevertWhen_InvalidStartTime() public {
    uint256[] memory matchIds = new uint256[](2);
    matchIds[0] = 1;
    matchIds[1] = 2;

    // Set up a timestamp in the past
    uint256 pastTime = block.timestamp - 1;
    
    vm.prank(admin);
    vm.expectRevert("Invalid start time");
    tournament.createTournament(
        "Test Tournament", 
        pastTime,  // Use explicit past time instead of arithmetic operation
        block.timestamp + 2 hours, 
        ENTRY_FEE, 
        matchIds
    );
}

function test_RevertWhen_NoMatches() public {
    uint256[] memory emptyMatchIds = new uint256[](0);
    
    vm.prank(admin);
    vm.expectRevert("No matches provided");
    tournament.createTournament(
        "Test Tournament", 
        block.timestamp + 1 hours, 
        block.timestamp + 2 hours, 
        ENTRY_FEE, 
        emptyMatchIds
    );
}

function test_RevertWhen_JoiningWithoutApproval() public {
    uint256[] memory matchIds = new uint256[](2);
    matchIds[0] = 1;
    matchIds[1] = 2;
    
    vm.prank(admin);
    tournament.createTournament(
        "Test Tournament", 
        block.timestamp + 1 hours, 
        block.timestamp + 2 hours, 
        ENTRY_FEE, 
        matchIds
    );

    vm.prank(user1);
    vm.expectRevert(); // Just expect any revert
    tournament.joinTournament(0);
}
function test_RevertWhen_DoubleJoining() public {
    uint256[] memory matchIds = new uint256[](2);
    matchIds[0] = 1;
    matchIds[1] = 2;
    
    vm.prank(admin);
    tournament.createTournament(
        "Test Tournament", 
        block.timestamp + 1 hours, 
        block.timestamp + 2 hours, 
        ENTRY_FEE, 
        matchIds
    );

    vm.startPrank(user1);
    token.approve(address(tournament), ENTRY_FEE);
    tournament.joinTournament(0);
    
    vm.expectRevert("Already joined");
    tournament.joinTournament(0);
    vm.stopPrank();
}

function test_RevertWhen_PredictingWithoutJoining() public {
    uint256[] memory matchIds = new uint256[](2);
    matchIds[0] = 1;
    matchIds[1] = 2;
    
    vm.prank(admin);
    tournament.createTournament(
        "Test Tournament", 
        block.timestamp + 1 hours, 
        block.timestamp + 2 hours, 
        ENTRY_FEE, 
        matchIds
    );

    vm.prank(user2);
    vm.expectRevert("Not participant");
    tournament.submitPrediction(0, 1, 1);
}

function test_RevertWhen_ClaimingWithNoRewards() public {
    uint256[] memory matchIds = new uint256[](2);
    matchIds[0] = 1;
    matchIds[1] = 2;
    
    vm.prank(admin);
    tournament.createTournament(
        "Test Tournament", 
        block.timestamp + 1 hours, 
        block.timestamp + 2 hours, 
        ENTRY_FEE, 
        matchIds
    );

    // Join tournament first
    vm.startPrank(user1);
    token.approve(address(tournament), ENTRY_FEE);
    tournament.joinTournament(0);
    
    // Try to claim without any rewards
    vm.warp(block.timestamp + 3 hours);
    vm.expectRevert("No rewards to claim");
    tournament.claimTournamentRewards(0);
    vm.stopPrank();

}    function testScoreUpdating() public {
        testPredictionSubmission();

        vm.startPrank(admin);
        address[] memory players = new address[](1);
        players[0] = user1;
        uint256[] memory matchScores = new uint256[](1);
        matchScores[0] = 10;

        tournament.updateScores(0, 1, players, matchScores);
        assertEq(tournament.scores(0, user1), 10);

        // Test length mismatch
        uint256[] memory invalidScores = new uint256[](2);
        vm.expectRevert("Length mismatch");
        tournament.updateScores(0, 1, players, invalidScores);
        vm.stopPrank();
    }
}
