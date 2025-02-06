// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BettingPool} from "../src/BettingPool.sol";
import {BetManager} from "../src/BetManager.sol";

contract DeployChainBets is Script {
    function run() external {
        // Get deployment variables from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address opTokenAddress = vm.envAddress("OP_TOKEN_ADDRESS");
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy main contracts
        BettingPool bettingPool = new BettingPool(opTokenAddress);
        BetManager betManager = new BetManager(address(bettingPool));

        // Setup initial configuration
        bettingPool.setProtocolFee(250); // 2.5%
        betManager.setOracle(oracleAddress, true);

        vm.stopBroadcast();

        // Log deployed addresses
        console2.log("Deployed BettingPool at:", address(bettingPool));
        console2.log("Deployed BetManager at:", address(betManager));
    }
}