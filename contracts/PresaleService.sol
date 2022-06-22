//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract PresaleService is AccessControl {
    uint256 private usageFee;
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    constructor(uint256 _usageFee) {
        _grantRole(ROLE_ADMIN, msg.sender);
        _setRoleAdmin(ROLE_ADMIN, ROLE_ADMIN);
        // TODO: Check if this is correct
        // usageFee = _usageFee / 10000;
    }

    /**
     * @dev
     *
     * @param startTimestamps list of start timestamps
     * @param endTimestamps list of end timestamps
     * @param prices list of prices
     * @param tokenAmtMantissas list of token amounts
     * @param erc20Token address of ERC20 token to sell at
     *
     * REQ: all lists have samne length
     */
    function startPresale(
        uint256[] memory startTimestamps,
        uint256[] memory endTimestamps,
        uint256[] memory prices,
        uint256[] memory tokenAmtMantissas,
        address erc20Token
    ) public {
        // Check lists are all same length
        // Think transitive property of ==
        require(
            startTimestamps.length == endTimestamps.length,
            "ERR: Lists must be same length"
        );
        require(
            endTimestamps.length == prices.length,
            "ERR: Lists must be same length"
        );
        require(
            prices.length == tokenAmtMantissas.length,
            "ERR: Lists must be same length"
        );
    }

    /**
     * @dev Exchange ETH for ERC20 token.
     *
     * @param presaleId presale id to exchange ETH for ERC20 tokens
     * @param tokenAmtMantissa amount of ERC20 tokens to receive given ETH
     */
    function buy(uint256 presaleId, uint256 tokenAmtMantissa) public {}

    /**
     * @dev Withdraw unsold tokens from an ended presale
     *
     * @param presaleId id of ended presale
     */
    function withdraw(uint256 presaleId) public {}

    /**
     * @dev
     *
     * @param presaleId presale to end
     */
    function endPresale(uint256 presaleId) public {}

    /**
     * @dev Change usage fee
     *
     * REQ: Must be admin
     */
    function changeUsageFee(uint256 _usageFee) public onlyRole(ROLE_ADMIN) {
        usageFee = _usageFee;
    }
}
