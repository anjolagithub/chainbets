// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBetManager {
    // Structs
    struct MatchMetadata {
        string gameType; // e.g., "LOL", "DOTA2"
        string teamA; // Team A name
        string teamB; // Team B name
        string tournament; // Tournament name
        string gameId; // External game ID for API integration
        uint256 timestamp; // Last updated timestamp
    }

    // Events
    event MatchMetadataSet(uint256 indexed matchId, string gameType, string teamA, string teamB);
    event OracleAddressSet(address indexed oracle);

    // Core Functions
    function setMatchMetadata(
        uint256 matchId,
        string memory gameType,
        string memory teamA,
        string memory teamB,
        string memory tournament,
        string memory gameId
    ) external;

    // View Functions
    function getMatchMetadata(uint256 matchId) external view returns (MatchMetadata memory);
    function isValidOracle(address oracle) external view returns (bool);
}
