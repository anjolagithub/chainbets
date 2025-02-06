// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBettingPool} from "./interfaces/IBettingPool.sol";

contract BettingPool is IBettingPool, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable bettingToken; // Ancient8 OP token
    uint256 public protocolFee = 250; // 2.5% in basis points
    uint256 public nextMatchId = 1;

    // Storage
    mapping(uint256 => Match) public matches;
    mapping(uint256 => mapping(address => Bet)) public userBets;
    mapping(address => uint256[]) public userBetHistory;

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
    }

    // Match Management Functions
    function createMatch(
        string memory name,
        uint256 startTime,
        uint256 endTime,
        uint256 minBet,
        uint256 maxBet
    ) external override onlyOwner {
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

    function placeBet(
        uint256 matchId,
        uint256 amount,
        uint8 prediction
    ) external override nonReentrant whenNotPaused matchExists(matchId) matchNotStarted(matchId) {
        Match storage match_ = matches[matchId];
        require(prediction == 1 || prediction == 2, "Invalid prediction");
        require(amount >= match_.minBet, "Bet too small");
        require(amount <= match_.maxBet, "Bet too large");
        require(userBets[matchId][msg.sender].amount == 0, "Already bet on this match");

        // Transfer tokens to contract
        bettingToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update pool totals first
        if (prediction == 1) {
            match_.totalPoolA += amount;
        } else {
            match_.totalPoolB += amount;
        }

        // Record bet
        userBets[matchId][msg.sender] = Bet({
            user: msg.sender,
            matchId: matchId,
            amount: amount,
            prediction: prediction,
            claimed: false
        });

        userBetHistory[msg.sender].push(matchId);

        emit BetPlaced(matchId, msg.sender, amount, prediction);
    }

    function finalizeMatch(
        uint256 matchId,
        uint8 winner
    ) external override onlyOwner matchExists(matchId) matchEnded(matchId) {
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

    function calculatePotentialWinnings(
        uint256 matchId,
        uint256 amount,
        uint8 prediction
    ) external view override returns (uint256) {
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