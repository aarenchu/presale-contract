//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title A general presale service
 * @author Aaren Chu
 * @dev work in progress
 */
contract PresaleService is AccessControl {
    /// @dev many presales can happen at once with same token
    /// @dev maintain mapping with unique id for every presale
    using Counters for Counters.Counter;
    struct Presale {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 price;
        uint256 tokenAmtMantissa;
        address token;
        bool buyUnlocked;
        bool withdrawUnlocked;
        bool isEnded;
    }
    mapping(uint256 => Presale) public presaleIdToPresale;
    Counters.Counter private presaleIds;
    uint256 private usageFee;
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
    IUniswapV2Router02 public uniswap;

    /**
     * Constructor
     *
     * @param _uniswap address of uniswap contract instance
     * @param _usageFee cost of usage fee, will be converted to bps
     */
    constructor(address _uniswap, uint256 _usageFee) {
        /// @dev set up admin address
        _grantRole(ROLE_ADMIN, msg.sender);
        _setRoleAdmin(ROLE_ADMIN, ROLE_ADMIN);
        /// @dev set up usage fee bp
        /// TODO: Check if this is correct
        usageFee = _usageFee / 10000;
        /// @dev set up uniswap
        uniswap = IUniswapV2Router02(_uniswap);
    }

    /**
     * Start presales
     *
     * @param startTimestamps list of start timestamps
     * @param endTimestamps list of end timestamps
     * @param prices list of prices
     * @param tokenAmtMantissas list of token amounts
     * @param token address of ERC20 token to sell at
     *
     * REQ: all lists have same length
     */
    function startPresale(
        uint256[] calldata startTimestamps,
        uint256[] calldata endTimestamps,
        uint256[] calldata prices,
        uint256[] calldata tokenAmtMantissas,
        address token
    ) external {
        /// @dev Check lists are all same length
        /// @dev Think transitive property of ==
        require(
            startTimestamps.length == endTimestamps.length,
            "Lists must be same length"
        );
        require(
            endTimestamps.length == prices.length,
            "Lists must be same length"
        );
        require(
            prices.length == tokenAmtMantissas.length,
            "Lists must be same length"
        );
        /// @dev create presales
        uint256 length = startTimestamps.length;
        uint256 _presaleId;
        for (uint8 i; i < length; i = _unsafeInc(i)) {
            _presaleId = presaleIds.current();
            presaleIdToPresale[_presaleId] = Presale(
                startTimestamps[i],
                endTimestamps[i],
                prices[i],
                tokenAmtMantissas[i],
                token,
                false,
                false,
                false
            );
            /// @dev TODO run??
            _runPresale(_presaleId);
            presaleIds.increment();
        }
    }

    /**
     * @dev Helper function to save gas costs on costly for-loops
     * from: https://moralis.io/how-to-reduce-solidity-gas-costs-full-guide/
     */
    function _unsafeInc(uint8 x) private pure returns (uint8) {
        unchecked {
            return x + 1;
        }
    }

    /**
     * @dev Helper function to run the presale
     *
     * @param presaleId id of presale to run
     */
    function _runPresale(uint256 presaleId) private {
        /// @dev get Presale
        Presale storage ps = presaleIdToPresale[presaleId];
        /// @dev user sends tokens to contract
        IERC20(ps.token).transferFrom(
            msg.sender,
            address(this),
            ps.tokenAmtMantissa
        );
        /// @dev buy functionality unlocked when start timestamp has been passed
        if (
            block.timestamp > ps.startTimestamp &&
            block.timestamp < ps.endTimestamp
        ) {
            ps.withdrawUnlocked = false;
            ps.buyUnlocked = true;
        }
        /// @dev when end timestamp passed, withdraw functionality unlocked
        /// @dev and the sale should end
        else if (block.timestamp > ps.endTimestamp) {
            ps.buyUnlocked = false;
            endPresale(presaleId, ps.token);
            ps.withdrawUnlocked = true;
        }
    }

    /**
     * Exchange ETH for ERC20 token.
     *
     * @param presaleId presale id to exchange ETH for ERC20 tokens
     * @param tokenAmtMantissa amount of tokens to receive
     *
     * REQ: Buy functionality of presale is unlocked
     */
    function buy(uint256 presaleId, uint256 tokenAmtMantissa) external {
        /// @dev get Presale
        Presale storage ps = presaleIdToPresale[presaleId];
        require(ps.buyUnlocked, "Buy functionality locked");
        address[] memory path = new address[](2);
        /// @dev first element is what you spend, second is what you get in return
        path[0] = uniswap.WETH();
        path[1] = ps.token;
        uniswap.swapETHForExactTokens(
            tokenAmtMantissa,
            path,
            msg.sender,
            ps.endTimestamp
        );
        /// @dev update token mantissa
        ps.tokenAmtMantissa = ps.tokenAmtMantissa - tokenAmtMantissa;
    }

    /**
     * Withdraw unsold tokens from an ended presale
     *
     * @param presaleId id of ended presale
     *
     * REQ: Presale is ended
     * REQ: Withdraw functionality of presale is unlocked
     */
    function withdraw(uint256 presaleId) external {
        /// @dev get Presale
        Presale memory ps = presaleIdToPresale[presaleId];
        require(ps.isEnded, "Presale is still active");
        require(ps.withdrawUnlocked, "Withdraw functionality locked");
        /// @dev don't waste gas transferring nothing
        if (ps.tokenAmtMantissa > 0)
            IERC20(ps.token).transfer(msg.sender, ps.tokenAmtMantissa);
    }

    /**
     * End presale given presale id
     *
     * @param presaleId presale to end
     * @param token address of ERC20 token to sell at
     *
     * REQ: end timestamp has passed
     * REQ: token must be the same as presale.
     */
    function endPresale(uint256 presaleId, address token) public {
        /// @dev get Presale
        Presale storage ps = presaleIdToPresale[presaleId];
        require(
            block.timestamp > ps.endTimestamp,
            "Presale end timestamp not passed"
        );
        require(token == ps.token, "Token is different");
        /// @dev The user will send to the contract the same amount of ERC20 token sold
        /// @dev TODO calculate amount
        uint256 amount = 0;
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        /// @dev both the token and ETH will be sent to uniswap as liquidity to create a trading pair.

        /// @dev Some ETH will go to the admin address based on the usage fee bp

        /// @dev Notify presale is ended
        ps.isEnded = true;
        /// @dev reset counter??
    }

    /**
     * Change usage fee
     *
     * @param _usageFee new usage fee to be converted to bps
     *
     * REQ: Must be admin
     */
    function changeUsageFee(uint256 _usageFee) external onlyRole(ROLE_ADMIN) {
        /// @dev set up basis points
        usageFee = _usageFee / 10000;
    }
}
