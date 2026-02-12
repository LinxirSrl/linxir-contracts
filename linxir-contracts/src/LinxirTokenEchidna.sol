// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/LinxirToken.sol";

contract LinxirTokenEchidna {

    LinxirToken token;

    uint256 constant MAX_SUPPLY = 2_000_000_000 ether;

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

    /// 🔒 Invariant 1: total supply never exceeds max
    function echidna_supply_never_exceeds_max() public view returns (bool) {
        return token.totalSupply() <= MAX_SUPPLY;
    }

    /// 🔒 Invariant 2: balance cannot exceed total supply
    function echidna_balance_consistency() public view returns (bool) {
        return token.balanceOf(address(this)) <= token.totalSupply();
    }

    /// 🔒 Invariant 3: usable balance cannot exceed total balance
    function echidna_usable_balance_safe() public view returns (bool) {
        return token.usableBalance(address(this)) <= token.balanceOf(address(this));
    }
}

