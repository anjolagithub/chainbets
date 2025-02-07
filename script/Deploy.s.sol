// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BettingPool} from "../src/BettingPool.sol";
import {Tournament} from "../src/Tournament.sol";
import {CommunityHub} from "../src/CommunityHub.sol";

contract DeployChainBets is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address opTokenAddress = vm.envAddress("OP_TOKEN_ADDRESS");

        require(opTokenAddress != address(0), "OP token address not set");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy BettingPool
        BettingPool bettingPool = new BettingPool(opTokenAddress);
        console2.log("BettingPool deployed at:", address(bettingPool));

        // Deploy Tournament
        Tournament tournament = new Tournament(address(bettingPool), opTokenAddress);
        console2.log("Tournament deployed at:", address(tournament));

        // Deploy CommunityHub
        CommunityHub communityHub = new CommunityHub(opTokenAddress);
        console2.log("CommunityHub deployed at:", address(communityHub));

        // Setup initial configuration
        bettingPool.setTournament(address(tournament));
        bettingPool.setCommunityHub(address(communityHub));
        bettingPool.setProtocolFee(250); // 2.5%

        vm.stopBroadcast();
    }
}
