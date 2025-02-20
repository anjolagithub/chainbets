// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockTournament {
    address public bettingPool;

    constructor(address _bettingPool) {
        bettingPool = _bettingPool;
    }
}
