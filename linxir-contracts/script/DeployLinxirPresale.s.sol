// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LinxirPresale.sol";

contract DeployLinxirPresale is Script {
    function run() external {
        vm.startBroadcast();

        address token = 0xd5f0b6A6AE5987AA8efa20572e1AA42A20e56F09; // LinxirToken
        address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT Mainnet
        address treasury = 0xC361921A8Fc11f8e2Fd81d316E7667111d824D2a; // treasury
        address ethUsdFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Chainlink Mainnet ETH/USD

        LinxirPresale presale = new LinxirPresale(
            token,
            usdt,
            treasury,
            ethUsdFeed
        );

        console2.log("LinxirPresale deployed at:", address(presale));

        vm.stopBroadcast();
    }
}


