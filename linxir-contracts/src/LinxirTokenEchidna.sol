// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/LinxirToken.sol";

contract LinxirTokenEchidna {
    LinxirToken token;

    constructor() {
        token = new LinxirToken(
            address(0x1),
            address(0x2),
            address(0x3),
            address(0x4),
            address(0x5),
            address(0x6)
        );
    }

    // Invariant base: la supply non deve MAI aumentare
    function echidna_supply_never_increases() public view returns (bool) {
        return token.totalSupply() <= 2_000_000_000 ether;
    }
}


