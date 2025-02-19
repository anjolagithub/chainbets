// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBettingPool {
    // Structs
    struct Match {
        uint256 id;
        string name;
        uint256 startTime;
        uint256 endTime;
        uint256 minBet;
        uint256 maxBet;
        bool isFinalized;
        uint8 winner; // 0: Not decided, 1: Team A, 2: Team B
        uint256 totalPoolA;
        uint256 totalPoolB;
    }

    struct Bet {
        address user;
        uint256 matchId;
        uint256 amount;
        uint8 prediction; // 1: Team A, 2: Team B
        bool claimed;
    }

    // Events
    event MatchCreated(uint256 indexed matchId, string name, uint256 startTime);
    event BetPlaced(uint256 indexed matchId, address indexed user, uint256 amount, uint8 prediction);
    event MatchFinalized(uint256 indexed matchId, uint8 winner);
    event WinningsClaimed(uint256 indexed matchId, address indexed user, uint256 amount);
    event ProtocolFeeUpdated(uint256 newFee);
    event EmergencyWithdraw(address token, uint256 amount);

    // Core Functions
    function createMatch(string memory name, uint256 startTime, uint256 endTime, uint256 minBet, uint256 maxBet)
        external;

    function placeBet(uint256 matchId, uint256 amount, uint8 prediction) external;
    
    // Tournament integration function
    function placeTournamentBet(address user, uint256 matchId, uint8 prediction) external;
    
    function finalizeMatch(uint256 matchId, uint8 winner) external;
    function claimWinnings(uint256 matchId) external;

    // View Functions
    function getMatch(uint256 matchId) external view returns (Match memory);
    function getUserBet(uint256 matchId, address user) external view returns (Bet memory);
    function getUserBetHistory(address user) external view returns (uint256[] memory);
    function calculatePotentialWinnings(uint256 matchId, uint256 amount, uint8 prediction)
        external
        view
        returns (uint256);

    // Admin Functions
    function setProtocolFee(uint256 newFee) external;
    function pause() external;
    function unpause() external;
    function emergencyWithdraw(address token) external;
}