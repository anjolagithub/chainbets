// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITournament} from "./interfaces/ITournament.sol";
import {IBettingPool} from "./interfaces/IBettingPool.sol";

contract Tournament is ITournament, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant TOURNAMENT_ADMIN = keccak256("TOURNAMENT_ADMIN");

    IBettingPool public immutable bettingPool;
    IERC20 public immutable token;

    mapping(uint256 => TournamentInfo) public tournaments;
    mapping(uint256 => mapping(address => bool)) public participants;
    mapping(uint256 => mapping(address => mapping(uint256 => uint8))) public predictions;
    mapping(uint256 => mapping(address => uint256)) public scores;

    uint256 public nextTournamentId;

    constructor(address _bettingPool, address _token) {
        require(_bettingPool != address(0), "Invalid betting pool");
        require(_token != address(0), "Invalid token");

        bettingPool = IBettingPool(_bettingPool);
        token = IERC20(_token);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(TOURNAMENT_ADMIN, msg.sender);
    }

    modifier tournamentActive(uint256 tournamentId) {
        require(tournaments[tournamentId].isActive, "Tournament not active");
        _;
    }

    modifier tournamentNotStarted(uint256 tournamentId) {
        require(block.timestamp < tournaments[tournamentId].startTime, "Tournament started");
        _;
    }

    modifier tournamentEnded(uint256 tournamentId) {
        require(block.timestamp > tournaments[tournamentId].endTime, "Tournament not ended");
        _;
    }

    function createTournament(
        string memory name,
        uint256 startTime,
        uint256 endTime,
        uint256 entryFee,
        uint256[] calldata matchIds
    ) external onlyRole(TOURNAMENT_ADMIN) {
        require(bytes(name).length > 0, "Invalid name");
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

    function joinTournament(uint256 tournamentId)
        external
        nonReentrant
        tournamentActive(tournamentId)
        tournamentNotStarted(tournamentId)
    {
        require(!participants[tournamentId][msg.sender], "Already joined");

        TournamentInfo storage tournament = tournaments[tournamentId];

        // Transfer entry fee
        if (tournament.entryFee > 0) {
            token.safeTransferFrom(msg.sender, address(this), tournament.entryFee);
            tournament.prizePool += tournament.entryFee;
        }

        participants[tournamentId][msg.sender] = true;
        emit PlayerJoined(tournamentId, msg.sender);
    }

    function submitPrediction(uint256 tournamentId, uint256 matchId, uint8 prediction)
        external
        tournamentActive(tournamentId)
        tournamentNotStarted(tournamentId)
    {
        require(participants[tournamentId][msg.sender], "Not participant");
        require(prediction == 1 || prediction == 2, "Invalid prediction");

        TournamentInfo storage tournament = tournaments[tournamentId];
        bool validMatch = false;
        for (uint256 i = 0; i < tournament.matchIds.length; i++) {
            if (tournament.matchIds[i] == matchId) {
                validMatch = true;
                break;
            }
        }
        require(validMatch, "Invalid match");

        predictions[tournamentId][msg.sender][matchId] = prediction;

        // Submit prediction to betting pool
        bettingPool.placeTournamentBet(msg.sender, matchId, prediction);

        emit PredictionSubmitted(tournamentId, matchId, msg.sender);
    }

    function claimTournamentRewards(uint256 tournamentId)
        external
        nonReentrant
        tournamentActive(tournamentId)
        tournamentEnded(tournamentId)
    {
        require(participants[tournamentId][msg.sender], "Not participant");

        uint256 playerScore = scores[tournamentId][msg.sender];
        require(playerScore > 0, "No rewards to claim");

        TournamentInfo storage tournament = tournaments[tournamentId];

        // Calculate reward based on score and prize pool
        uint256 totalScore = getTotalScore(tournamentId);
        require(totalScore > 0, "No total score");

        uint256 reward = (tournament.prizePool * playerScore) / totalScore;
        require(reward > 0, "No reward");

        tournament.prizePool -= reward;

        // Reset player score to prevent multiple claims
        scores[tournamentId][msg.sender] = 0;

        // Transfer reward
        token.safeTransfer(msg.sender, reward);
    }

    // Admin functions
    function finalizeTournament(uint256 tournamentId, address[] calldata winners)
        external
        onlyRole(TOURNAMENT_ADMIN)
        tournamentActive(tournamentId)
        tournamentEnded(tournamentId)
    {
        TournamentInfo storage tournament = tournaments[tournamentId];
        tournament.isActive = false;
        emit TournamentFinalized(tournamentId, winners);
    }

    function updateScores(
        uint256 tournamentId,
        uint256 matchId,
        address[] calldata players,
        uint256[] calldata matchScores
    ) external onlyRole(TOURNAMENT_ADMIN) tournamentActive(tournamentId) {
        require(players.length == matchScores.length, "Length mismatch");

        // Validate match belongs to tournament
        TournamentInfo storage tournament = tournaments[tournamentId];
        bool validMatch = false;
        for (uint256 i = 0; i < tournament.matchIds.length; i++) {
            if (tournament.matchIds[i] == matchId) {
                validMatch = true;
                break;
            }
        }
        require(validMatch, "Invalid match");

        // Update scores
        for (uint256 i = 0; i < players.length; i++) {
            require(participants[tournamentId][players[i]], "Invalid participant");
            scores[tournamentId][players[i]] += matchScores[i];
        }
    }

    // View functions
    function getTotalScore(uint256 tournamentId) public view returns (uint256) {
        uint256 total = 0;
        TournamentInfo storage tournament = tournaments[tournamentId];
        for (uint256 i = 0; i < tournament.matchIds.length; i++) {
            uint256 matchId = tournament.matchIds[i];
            // Sum up all participants' scores for this match
            mapping(address => uint256) storage matchScores = scores[tournamentId];
            total += matchScores[msg.sender];
        }
        return total;
    }

    function getPlayerScore(uint256 tournamentId, address player) external view returns (uint256) {
        return scores[tournamentId][player];
    }

    // Admin management functions
    function addTournamentAdmin(address admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(admin != address(0), "Invalid admin address");
        grantRole(TOURNAMENT_ADMIN, admin);
    }

    function removeTournamentAdmin(address admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(admin != address(0), "Invalid admin address");
        revokeRole(TOURNAMENT_ADMIN, admin);
    }
}
