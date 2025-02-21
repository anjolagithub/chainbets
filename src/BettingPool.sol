// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBettingPool} from "./interfaces/IBettingPool.sol";

interface ICommunityHub {
    function updateUserActivity(address user, uint256 amount) external;
    function processWinnings(address user, uint256 amount) external;
}

contract BettingPool is IBettingPool, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable bettingToken;
    uint256 public protocolFee;
    uint256 public nextMatchId;

    // Integration contracts
    address public tournament;
    address public communityHub;

    // Storage
    mapping(uint256 => Match) public matches;
    mapping(uint256 => mapping(address => Bet)) public userBets;
    mapping(address => uint256[]) public userBetHistory;

    // Events
    event TournamentSet(address indexed tournament);
    event CommunityHubSet(address indexed communityHub);
    event DebugEvent(string message, uint256 value);

    // Modifiers
    modifier matchExists(uint256 matchId) {
        require(matches[matchId].id == matchId, "Match does not exist");
        _;
    }

    modifier matchNotStarted(uint256 matchId) {
        require(block.timestamp < matches[matchId].startTime, "Match already started");
        _;
    }

    modifier matchEnded(uint256 matchId) {
        require(block.timestamp > matches[matchId].endTime, "Match not ended");
        _;
    }

    constructor(address _bettingToken) Ownable(msg.sender) {
        require(_bettingToken != address(0), "Invalid token address");
        bettingToken = IERC20(_bettingToken);
        protocolFee = 250; // Initialize at 2.5%
        nextMatchId = 1; // Initialize at 1
    }

    // Explicit getter functions
    function getNextMatchId() public view returns (uint256) {
        return nextMatchId;
    }

    function getProtocolFee() public view returns (uint256) {
        return protocolFee;
    }

    // Integration setters
    function setTournament(address _tournament) external onlyOwner {
        require(_tournament != address(0), "Invalid tournament address");
        tournament = _tournament;
        emit TournamentSet(_tournament);
    }

    function setCommunityHub(address _communityHub) external onlyOwner {
        require(_communityHub != address(0), "Invalid community hub address");
        communityHub = _communityHub;
        emit CommunityHubSet(_communityHub);
    }

    // Match Management Functions
    function createMatch(string memory name, uint256 startTime, uint256 endTime, uint256 minBet, uint256 maxBet)
        external
        override
    {
        require(bytes(name).length > 0, "Invalid name");
        require(startTime > block.timestamp, "Invalid start time");
        require(endTime > startTime, "Invalid end time");
        require(minBet > 0 && maxBet > minBet, "Invalid bet limits");

        uint256 matchId = nextMatchId++;

        matches[matchId] = Match({
            id: matchId,
            name: name,
            startTime: startTime,
            endTime: endTime,
            minBet: minBet,
            maxBet: maxBet,
            isFinalized: false,
            winner: 0,
            totalPoolA: 0,
            totalPoolB: 0
        });

        emit MatchCreated(matchId, name, startTime);
    }

    function validateBetParameters(uint256 matchId, uint256 amount, uint8 prediction) public view returns (bool) {
        require(bettingToken.balanceOf(msg.sender) >= amount, "Insufficient token balance");
        require(bettingToken.allowance(msg.sender, address(this)) >= amount, "Insufficient token allowance");
        require(matchId > 0 && matchId < nextMatchId && matches[matchId].id == matchId, "Match does not exist");
        require(block.timestamp < matches[matchId].startTime, "Match already started");
        require(prediction == 1 || prediction == 2, "Invalid prediction");
        require(amount > 0, "Invalid amount");
        require(amount >= matches[matchId].minBet, "Bet too small");
        require(amount <= matches[matchId].maxBet, "Bet too large");
        require(userBets[matchId][msg.sender].amount == 0, "Already bet on this match");
        return true;
    }

    function placeBet(uint256 matchId, uint256 amount, uint8 prediction) external override //nonReentrant 
    whenNotPaused{
        emit DebugEvent("Entered placeBet", matchId);

        require(matchId > 0 && matchId < nextMatchId && matches[matchId].id == matchId, "Match does not exist");
        emit DebugEvent("Match exists", matchId);

        Match storage match_ = matches[matchId];
        require(block.timestamp < match_.startTime, "Match already started");
        emit DebugEvent("Match not started", match_.startTime);

        require(prediction == 1 || prediction == 2, "Invalid prediction");
        emit DebugEvent("Prediction valid", prediction);

        require(amount > 0, "Invalid amount");
        emit DebugEvent("Amount valid", amount);

        require(amount >= match_.minBet, "Bet too small");
        require(amount <= match_.maxBet, "Bet too large");
        emit DebugEvent("Bet within limits", amount);

        require(userBets[matchId][msg.sender].amount == 0, "Already bet on this match");
        emit DebugEvent("No duplicate bet", matchId);

        uint256 userBalance = bettingToken.balanceOf(msg.sender);
        uint256 userAllowance = bettingToken.allowance(msg.sender, address(this));
        require(userBalance >= amount, "Insufficient token balance");
        require(userAllowance >= amount, "Insufficient token allowance");
        emit DebugEvent("Balance and allowance valid", userBalance);

        bettingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit DebugEvent("Token transfer successful", amount);

        userBets[matchId][msg.sender] =
            Bet({user: msg.sender, matchId: matchId, amount: amount, prediction: prediction, claimed: false});

        if (prediction == 1) {
            match_.totalPoolA += amount;
        } else {
            match_.totalPoolB += amount;
        }

        userBetHistory[msg.sender].push(matchId);
        emit DebugEvent("State updated", matchId);

        // if (communityHub != address(0)) {
        //     ICommunityHub(communityHub).updateUserActivity(msg.sender, amount);
        //     emit DebugEvent("Community hub updated", amount);
        // }

        emit BetPlaced(matchId, msg.sender, amount, prediction);
    }

     function placeTournamentBet(
        address user,
        uint256 matchId,
        uint8 prediction
    ) external override matchExists(matchId) matchNotStarted(matchId) {
        require(msg.sender == tournament, "Only tournament");

        // Record bet without token transfer
        userBets[matchId][user] = Bet({
            user: user,
            matchId: matchId,
            amount: 0, // Tournament bets don't lock tokens
            prediction: prediction,
            claimed: false
        });

        userBetHistory[user].push(matchId);

        emit BetPlaced(matchId, user, 0, prediction);
    }


    function finalizeMatch(uint256 matchId, uint8 winner) external override matchExists(matchId) matchEnded(matchId) {
        Match storage match_ = matches[matchId];
        require(!match_.isFinalized, "Match already finalized");
        require(winner == 1 || winner == 2, "Invalid winner");

        match_.winner = winner;
        match_.isFinalized = true;

        emit MatchFinalized(matchId, winner);
    }

    function claimWinnings(uint256 matchId) external override nonReentrant matchExists(matchId) {
        Match storage match_ = matches[matchId];
        require(match_.isFinalized, "Match not finalized");

        Bet storage bet = userBets[matchId][msg.sender];
        require(bet.amount > 0, "No bet placed");
        require(!bet.claimed, "Already claimed");
        require(bet.prediction == match_.winner, "Bet did not win");

        bet.claimed = true;

        // Calculate winnings
        uint256 winningPool = match_.winner == 1 ? match_.totalPoolA : match_.totalPoolB;
        uint256 totalPool = match_.totalPoolA + match_.totalPoolB;
        uint256 winnings = (bet.amount * totalPool) / winningPool;

        // Apply protocol fee
        uint256 fee = (winnings * protocolFee) / 10000;
        winnings -= fee;

        // Transfer winnings
        bettingToken.safeTransfer(msg.sender, winnings);

        // Notify community hub if set
        if (communityHub != address(0)) {
            ICommunityHub(communityHub).processWinnings(msg.sender, winnings);
        }

        emit WinningsClaimed(matchId, msg.sender, winnings);
    }

    // View Functions
    function getMatch(uint256 matchId) external view override returns (Match memory) {
        return matches[matchId];
    }

    function getUserBet(uint256 matchId, address user) external view override returns (Bet memory) {
        return userBets[matchId][user];
    }

    function getUserBetHistory(address user) external view override returns (uint256[] memory) {
        return userBetHistory[user];
    }

    function calculatePotentialWinnings(uint256 matchId, uint256 amount, uint8 prediction)
        external
        view
        override
        returns (uint256)
    {
        Match storage match_ = matches[matchId];
        uint256 relevantPool = prediction == 1 ? match_.totalPoolA : match_.totalPoolB;
        uint256 totalPool = match_.totalPoolA + match_.totalPoolB;

        if (relevantPool == 0) return amount * 2; // Initial odds 1:1

        uint256 potentialWinnings = (amount * totalPool) / relevantPool;
        uint256 fee = (potentialWinnings * protocolFee) / 10000;
        return potentialWinnings - fee;
    }

    // Admin Functions
    function setProtocolFee(uint256 newFee) external override onlyOwner {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        protocolFee = newFee;
        emit ProtocolFeeUpdated(newFee);
    }

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(address token) external override onlyOwner {
        require(token != address(0), "Invalid token");
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");

        tokenContract.safeTransfer(owner(), balance);
        emit EmergencyWithdraw(token, balance);
    }
}
