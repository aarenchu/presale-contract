// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MLPToken is ERC20 {
    address public owner;

    constructor(uint256 initialPayout) ERC20("MockLP", "MLP") {
        owner = msg.sender;
        // MLP is stored in decimals like ether to wei
        _mint(msg.sender, initialPayout * 10**uint256(decimals()));
    }
}
