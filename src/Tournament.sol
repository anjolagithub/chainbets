// src/Tournament.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITournament} from "./interfaces/ITournament.sol";
import {IBettingPool} from "./interfaces/IBettingPool.sol";

contract Tournament is ITournament, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IBettingPool public immutable bettingPool;
    IERC20 public immutable token;
    
    mapping(uint256 => TournamentInfo) public tournaments;
    mapping(uint256 => mapping(address => bool)) public participants;
    mapping(uint256 => mapping(address => mapping(uint256 => uint8))) public predictions;
    mapping(uint256 => mapping(address => uint256)) public scores;
    
    uint256 public nextTournamentId;

    constructor(address _bettingPool, address _token) Ownable(msg.sender) {
        bettingPool = IBettingPool(_bettingPool);
        token = IERC20(_token);
    }

    function createTournament(
        string memory name,
        uint256 startTime,
        uint256 endTime,
        uint256 entryFee,
        uint256[] calldata matchIds
    ) external onlyOwner {
        require(startTime > block.timestamp, "Invalid start time");
        require(endTime > startTime, "Invalid end time");
        require(matchIds.length > 0, "No matches provided");

        uint256 tournamentId = nextTournamentId++;
        tournaments[tournamentId] = TournamentInfo({
            id: tournamentId,
            name: name,
            startTime: startTime,
            endTime: endTime,
            entryFee: entryFee,
            prizePool: 0,
            isActive: true,
            matchIds: matchIds
        });

        emit TournamentCreated(tournamentId, name, startTime);
    }

    function joinTournament(uint256 tournamentId) external nonReentrant {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.isActive, "Tournament not active");
        require(block.timestamp < tournament.startTime, "Tournament started");
        require(!participants[tournamentId][msg.sender], "Already joined");

        // Transfer entry fee
        if (tournament.entryFee > 0) {
            token.safeTransferFrom(msg.sender, address(this), tournament.entryFee);
            tournament.prizePool += tournament.entryFee;
        }

        participants[tournamentId][msg.sender] = true;
        emit PlayerJoined(tournamentId, msg.sender);
    }

    function submitPrediction(
        uint256 tournamentId,
        uint256 matchId,
        uint8 prediction
    ) external {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.isActive, "Tournament not active");
        require(participants[tournamentId][msg.sender], "Not participant");
        require(block.timestamp < tournament.startTime, "Tournament started");
        
        bool validMatch = false;
        for (uint256 i = 0; i < tournament.matchIds.length; i++) {
            if (tournament.matchIds[i] == matchId) {
                validMatch = true;
                break;
            }
        }
        require(validMatch, "Invalid match");

        predictions[tournamentId][msg.sender][matchId] = prediction;
        emit PredictionSubmitted(tournamentId, matchId, msg.sender);
    }

    function claimTournamentRewards(uint256 tournamentId) external nonReentrant {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.isActive, "Tournament not active");
        require(block.timestamp > tournament.endTime, "Tournament not ended");
        require(participants[tournamentId][msg.sender], "Not participant");
        
        uint256 playerScore = scores[tournamentId][msg.sender];
        require(playerScore > 0, "No rewards to claim");

        // Calculate reward based on score and prize pool
        uint256 reward = (tournament.prizePool * playerScore) / getTotalScore(tournamentId);
        tournament.prizePool -= reward;
        
        // Transfer reward
        token.safeTransfer(msg.sender, reward);
    }

    function getTotalScore(uint256 tournamentId) public view returns (uint256) {
        uint256 total = 0;
        TournamentInfo storage tournament = tournaments[tournamentId];
        for (uint256 i = 0; i < tournament.matchIds.length; i++) {
            // Sum up scores for each match
            total += scores[tournamentId][msg.sender];
        }
        return total;
    }

    // Admin function to update scores after matches
    function updateScores(
        uint256 tournamentId,
        uint256 matchId,
        address[] calldata players,
        uint256[] calldata matchScores
    ) external onlyOwner {
        require(players.length == matchScores.length, "Length mismatch");
        
        for (uint256 i = 0; i < players.length; i++) {
            scores[tournamentId][players[i]] += matchScores[i];
        }
    }
}