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
    // many presales can happen at once with same token
    // maintain mapping with unique id for every presale
    using Counters for Counters.Counter;
    struct Presale {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 price;
        uint256 ogTokenAmtMantissa;
        uint256 tokenAmtMantissa;
        address token;
        bool isEnded;
    }
    mapping(uint256 => Presale) public presaleIdToPresale;
    Counters.Counter public presaleIds;
    uint256 public usageFeeBps;
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
    address public admin;
    uint256 public constant MAX_INT = 2**256 - 1;
    IUniswapV2Router02 public uniswap;

    /**
     * Constructor
     *
     * @param _uniswap address of uniswap contract instance
     * @param _usageFeeBps cost of usage fee in bps
     */
    constructor(address _uniswap, uint256 _usageFeeBps) {
        // set up admin address
        _grantRole(ROLE_ADMIN, msg.sender);
        _setRoleAdmin(ROLE_ADMIN, ROLE_ADMIN);
        admin = msg.sender;
        // set up usage fee bps
        usageFeeBps = _usageFeeBps;
        // set up uniswap
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
        // Check lists are all same length
        // Think transitive property of ==
        require(
            startTimestamps.length == endTimestamps.length &&
                endTimestamps.length == prices.length &&
                prices.length == tokenAmtMantissas.length,
            "Lists must be same length"
        );
        // approve transferFroms
        if (IERC20(token).allowance(msg.sender, address(this)) == 0)
            IERC20(token).approve(address(this), MAX_INT);
        if (IERC20(token).allowance(address(this), msg.sender) == 0)
            IERC20(token).approve(msg.sender, MAX_INT);
        // create presales
        uint256 length = startTimestamps.length;
        uint256 _presaleId;
        for (uint8 i; i < length; i = _unsafeInc(i)) {
            _presaleId = presaleIds.current();
            presaleIdToPresale[_presaleId] = Presale(
                startTimestamps[i],
                endTimestamps[i],
                prices[i],
                tokenAmtMantissas[i],
                tokenAmtMantissas[i],
                token,
                false
            );
            // user sends tokens to contract
            IERC20(token).transferFrom(
                msg.sender,
                address(this),
                tokenAmtMantissas[i]
            );
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
     * Exchange ETH for ERC20 token.
     *
     * @param presaleId presale id to exchange ETH for ERC20 tokens
     * @param tokenAmtMantissa amount of tokens to receive
     *
     * REQ: Buy functionality of presale is unlocked
     */
    function buy(uint256 presaleId, uint256 tokenAmtMantissa) external {
        // get Presale
        Presale storage ps = presaleIdToPresale[presaleId];
        // buy functionality unlocked when start timestamp has been passed
        require(block.timestamp > ps.startTimestamp, "Sale not started");
        require(
            block.timestamp < ps.endTimestamp && !ps.isEnded,
            "Sale is ended."
        );
        address[] memory path = new address[](2);
        // first element is what you spend, second is what you get in return
        path[0] = uniswap.WETH();
        path[1] = ps.token;
        uniswap.swapETHForExactTokens(
            tokenAmtMantissa * ps.price,
            path,
            msg.sender,
            ps.endTimestamp
        );
        // update token mantissa
        ps.tokenAmtMantissa = ps.tokenAmtMantissa - tokenAmtMantissa;
    }

    /**
     * Withdraw unsold tokens from an ended presale
     *
     * @param presaleId id of ended presale
     *
     * REQ: Presale is ended
     * REQ: Past the end timestamp
     */
    function withdraw(uint256 presaleId) external {
        // get Presale
        Presale memory ps = presaleIdToPresale[presaleId];
        require(
            block.timestamp > ps.endTimestamp && ps.isEnded,
            "Presale is still active"
        );
        // don't waste gas transferring nothing
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
     * REQ: user has the same # of tokens that were sold?
     */
    function endPresale(uint256 presaleId, address token) public payable {
        // get Presale
        Presale storage ps = presaleIdToPresale[presaleId];
        require(
            block.timestamp > ps.endTimestamp,
            "Presale end timestamp not passed"
        );
        require(token == ps.token, "Token is different");
        // The user will send to the contract the same amount of ERC20 token sold
        uint256 amount = (ps.ogTokenAmtMantissa - ps.tokenAmtMantissa) *
            ps.price;
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        // 1% tolerance (100bps)
        uint256 amountTokenMin = amount - ((amount * 100) / 10000);
        uint256 amountETHMin = msg.value - ((msg.value * 100) / 10000);
        // approve uniswap
        if (IERC20(token).allowance(address(this), address(uniswap)) == 0)
            IERC20(token).approve(address(uniswap), MAX_INT);
        // both the token and ETH will be sent to uniswap as liquidity to create a trading pair.
        (, uint256 amountEth, ) = uniswap.addLiquidityETH(
            token,
            amount,
            amountTokenMin,
            amountETHMin,
            address(this),
            block.timestamp + 30 minutes
        );
        // Some ETH will go to the admin address based on the usage fee bp
        IERC20(uniswap.WETH()).transfer(
            admin,
            (amountEth * usageFeeBps) / 10000
        );
        // Notify presale is ended
        ps.isEnded = true;
    }

    /**
     * Change usage fee
     *
     * @param _usageFeeBps new usage fee in bps
     *
     * REQ: Must be admin
     */
    function changeUsageFee(uint256 _usageFeeBps)
        external
        onlyRole(ROLE_ADMIN)
    {
        // set up basis points
        usageFeeBps = _usageFeeBps;
    }
}
