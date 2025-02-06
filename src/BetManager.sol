// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBetManager} from "./interfaces/IBetManager.sol";
import {IBettingPool} from "./interfaces/IBettingPool.sol";

contract BetManager is IBetManager, Ownable {
    // State variables
    IBettingPool public immutable bettingPool;
    mapping(uint256 => MatchMetadata) public matchMetadata;
    mapping(address => bool) public oracles;

    // Events
    event OracleUpdated(address indexed oracle, bool isValid);

    // Modifiers
    modifier onlyOracle() {
        require(oracles[msg.sender], "Not authorized oracle");
        _;
    }

    constructor(address _bettingPool) Ownable(msg.sender) {
        require(_bettingPool != address(0), "Invalid betting pool");
        bettingPool = IBettingPool(_bettingPool);
    }

    // Oracle Management
    function setOracle(address oracle, bool isValid) external onlyOwner {
        require(oracle != address(0), "Invalid oracle address");
        oracles[oracle] = isValid;
        emit OracleUpdated(oracle, isValid);
    }

    // Match Metadata Management
    function setMatchMetadata(
        uint256 matchId,
        string memory gameType,
        string memory teamA,
        string memory teamB,
        string memory tournament,
        string memory gameId
    ) external override onlyOracle {
        require(bytes(gameType).length > 0, "Invalid game type");
        require(bytes(teamA).length > 0, "Invalid team A");
        require(bytes(teamB).length > 0, "Invalid team B");

        matchMetadata[matchId] = MatchMetadata({
            gameType: gameType,
            teamA: teamA,
            teamB: teamB,
            tournament: tournament,
            gameId: gameId,
            timestamp: block.timestamp
        });

        emit MatchMetadataSet(matchId, gameType, teamA, teamB);
    }

    // View Functions
    function getMatchMetadata(uint256 matchId) external view override returns (MatchMetadata memory) {
        return matchMetadata[matchId];
    }

    function isValidOracle(address oracle) external view override returns (bool) {
        return oracles[oracle];
    }
}