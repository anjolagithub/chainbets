// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITournament {
    struct TournamentInfo {
        uint256 id;
        string name;
        uint256 startTime;
        uint256 endTime;
        uint256 entryFee;
        uint256 prizePool;
        bool isActive;
        uint256[] matchIds;
    }

    event TournamentCreated(uint256 indexed id, string name, uint256 startTime);
    event PlayerJoined(uint256 indexed tournamentId, address indexed player);
    event PredictionSubmitted(uint256 indexed tournamentId, uint256 indexed matchId, address indexed player);
    event TournamentFinalized(uint256 indexed id, address[] winners);

    function createTournament(
        string memory name,
        uint256 startTime,
        uint256 endTime,
        uint256 entryFee,
        uint256[] calldata matchIds
    ) external;

    function joinTournament(uint256 tournamentId) external;
    function submitPrediction(uint256 tournamentId, uint256 matchId, uint8 prediction) external;
    function claimTournamentRewards(uint256 tournamentId) external;
}
