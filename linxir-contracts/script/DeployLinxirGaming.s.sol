// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LinxirGaming} from "../src/LinxirGaming.sol";

contract DeployLinxirGaming is Script {
    function run() external {
        // ✅ Inserisci il tuo indirizzo del token già deployato
        address tokenAddress = 0x3D5556bc4d339a46456b42eBf1cf0F7c59BeE70A;

        // ✅ Start broadcast
        vm.startBroadcast();

        // 🚀 Deploy del contratto Gaming
        LinxirGaming gaming = new LinxirGaming(tokenAddress);
        console2.log("LinxirGaming deployed at:", address(gaming));

        // ✅ Stop broadcast
        vm.stopBroadcast();
    }
}
