//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v2-periphery/contracts/UniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapMock is UniswapV2Router02 {
    IERC20 public mlp;
    address public owner;

    constructor(IERC20 _mlp) {
        owner = msg.sender;
        mlp = _mlp;
    }
}
