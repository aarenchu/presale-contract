// contracts/MOKToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MOKToken is ERC20 {
    address public owner;

    constructor(uint256 initialPayout) ERC20("Mok", "MOK") {
        owner = msg.sender;
        // MOK is stored in decimals like ether to wei
        _mint(msg.sender, initialPayout * 10**uint256(decimals()));
    }
}
