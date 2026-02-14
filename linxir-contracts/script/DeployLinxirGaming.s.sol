// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LinxirGaming} from "../src/LinxirGaming.sol";

contract DeployLinxirGaming is Script {
    function run() external {
        address tokenAddress = 0xd5f0b6A6AE5987AA8efa20572e1AA42A20e56F09;

        vm.startBroadcast();

        LinxirGaming gaming = new LinxirGaming(tokenAddress);
        console2.log("LinxirGaming deployed at:", address(gaming));

        vm.stopBroadcast();
    }
}
