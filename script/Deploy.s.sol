// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BettingPool} from "../src/BettingPool.sol";
import {Tournament} from "../src/Tournament.sol";
import {CommunityHub} from "../src/CommunityHub.sol";

contract DeployChainBets is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address opTokenAddress = vm.envAddress("OP_TOKEN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy main contracts
        BettingPool bettingPool = new BettingPool(opTokenAddress);
        console2.log("BettingPool deployed at:", address(bettingPool));

        Tournament tournament = new Tournament(
            address(bettingPool),
            opTokenAddress
        );
        console2.log("Tournament deployed at:", address(tournament));

        CommunityHub communityHub = new CommunityHub(opTokenAddress);
        console2.log("CommunityHub deployed at:", address(communityHub));

        // Setup contract connections
        bettingPool.setTournament(address(tournament));
        bettingPool.setCommunityHub(address(communityHub));

        // Set initial protocol fee
        bettingPool.setProtocolFee(250); // 2.5%

        vm.stopBroadcast();

        // Save deployment info
        string memory deploymentInfo = string(
            abi.encodePacked(
                "Deployment timestamp: ",
                vm.toString(block.timestamp),
                "\nBettingPool: ",
                vm.toString(address(bettingPool)),
                "\nTournament: ",
                vm.toString(address(tournament)),
                "\nCommunityHub: ",
                vm.toString(address(communityHub))
            )
        );
        vm.writeFile("./deployments.txt", deploymentInfo);
    }
}