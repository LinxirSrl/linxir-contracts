// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LinxirGaming} from "../src/LinxirGaming.sol";

contract DeployLinxirGaming is Script {
    function run() external {
        address tokenAddress = 0x1bd05590ab5cb8Aa541a0F997Ba0B40f9570124C;

        vm.startBroadcast();

        LinxirGaming gaming = new LinxirGaming(tokenAddress);
        console2.log("LinxirGaming deployed at:", address(gaming));

        vm.stopBroadcast();
    }
}
