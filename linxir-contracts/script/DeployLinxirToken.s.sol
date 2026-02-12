// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LinxirToken.sol";

contract DeployLinxirToken is Script {
    function run() external {
        vm.startBroadcast();

        address presale = address(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
        address staking = address(0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db);
        address liquidity = address(0xe6eDBEa1C67834B196e1cf558F00D40483E4Dc33);
        address team = address(0x8B09e8F6278011B89AFafa5469C6108782c427Ae);
        address marketing = address(0x9532ac424758631A90312bF1F9C7c4D4c115cAE7);
        address gaming = address(0x17F6AD8Ef982297579C203069C1DbfFE4348c372);

        LinxirToken token = new LinxirToken(
            presale,
            staking,
            liquidity,
            team,
            marketing,
            gaming
        );

        console2.log("LinxirToken deployed at:", address(token));

        vm.stopBroadcast();
    }
}
