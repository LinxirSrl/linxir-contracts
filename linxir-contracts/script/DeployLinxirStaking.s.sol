// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LinxirStaking.sol";
import "../src/LinxirToken.sol";

contract DeployLinxirStaking is Script {
    function run() external {
        vm.startBroadcast();

        address tokenAddress = 0xd5f0b6A6AE5987AA8efa20572e1AA42A20e56F09;

        LinxirStaking staking = new LinxirStaking(tokenAddress);
        console2.log("LinxirStaking deployed at:", address(staking));

        vm.stopBroadcast();
    }
}

