// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LinxirStaking.sol";
import "../src/LinxirToken.sol"; // se serve il type casting esplicito

contract DeployLinxirStaking is Script {
    function run() external {
        vm.startBroadcast();

        // ✅ Indirizzo reale del token Linxir già deployato
        address tokenAddress = 0x1bd05590ab5cb8Aa541a0F997Ba0B40f9570124C;

        // 🏗️ Deploy contratto staking
        LinxirStaking staking = new LinxirStaking(tokenAddress);
        console2.log("LinxirStaking deployed at:", address(staking));

        vm.stopBroadcast();
    }
}

