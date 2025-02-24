// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BettingPool} from "../src/BettingPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract RecoverFunds is Script {
    address constant OLD_BETTING_POOL = 0x792f1fB27F6B61f030469acdCf397c8444d6BF2B;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant FRONTEND_DEV = 0x3785717c152BFe807cD2929CbeCC1500af651404;
    
    function run() external {
        // Check balance first
        IERC20 weth = IERC20(WETH);
        uint256 balance = weth.balanceOf(OLD_BETTING_POOL);
        console2.log("WETH Balance in old contract:", balance);

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        // Recover WETH
        BettingPool pool = BettingPool(OLD_BETTING_POOL);
        pool.emergencyWithdraw(WETH);

        // Transfer to frontend dev
        weth.transfer(FRONTEND_DEV, balance);

        vm.stopBroadcast();
    }
}