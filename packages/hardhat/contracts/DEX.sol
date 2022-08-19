// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    using SafeMath for uint256; //outlines use of SafeMath for uint256 variables
    IERC20 token; //instantiates the imported contract

    uint public totalLiquidity;
    mapping(address => uint) public liquidity;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(address indexed trader, string action, uint ethInput, uint tokenOutput);

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(address indexed trader, string action, uint tokenInput, uint ethOutput);

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided(address indexed liquidityProvider, uint liquidityAmount, uint ethAmount, uint tokenAmount);

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved(address indexed liquidityProvider, uint liquidityAmount, uint ethAmount, uint tokenAmount);

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr) public {
        token = IERC20(token_addr); //specifies the token add ress that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens) public payable returns (uint256) {

        require(totalLiquidity == 0, "Fail: can't call init if totalLiquidity != 0");

        totalLiquidity = address(this).balance;
        liquidity[msg.sender] = totalLiquidity;

        require(token.transferFrom(msg.sender, address(this), tokens), "Failed to transfer!");

        return totalLiquidity;

    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done.
     */
    function price(uint256 xInput, uint256 xReserves, uint256 yReserves) public pure returns (uint256 yOutput) {

        uint256 xInputWithFee = xInput.mul(997);
        
        uint256 numerator = xInputWithFee.mul(yReserves);
        uint256 denominator = (xReserves.mul(1000)).add(xInputWithFee);

        return (numerator / denominator);

    }

    /**
     * @notice returns liquidity for a user. Note this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
     * if you are using a mapping liquidity, then you can use `return liquidity[lp]` to get the liquidity for a user.
     *
     */
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL
     */
    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(msg.value > 0, "Provide ETH to swap!");

        uint xReserve = address(this).balance - msg.value;
        uint yReserve = token.balanceOf(address(this));

        tokenOutput = price(msg.value, xReserve, yReserve);

        require(token.transfer(msg.sender, tokenOutput), "Token transfer failed!");

        emit EthToTokenSwap(msg.sender, "ETH to Token", msg.value, tokenOutput);

    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether
     */
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        require(tokenInput > 0, "Proved Tokens to swap!");

        uint xReserve = token.balanceOf(address(this));
        uint yReserve = address(this).balance;

        ethOutput = price(tokenInput, xReserve, yReserve);

        require(token.transferFrom(msg.sender, address(this), tokenInput), "Token transfer failed!");

        (bool success, ) = msg.sender.call{value: ethOutput}("");
        require(success, "ETH transfer failed!");

        emit TokenToEthSwap(msg.sender, "Token to ETH", tokenInput, ethOutput);

    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
     * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
     * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
     */
    function deposit() public payable returns (uint256 tokenAmount) {

        uint ethReserve = address(this).balance - msg.value;
        uint tokenReserve = token.balanceOf(address(this));

        ///xDeposit = yDeposit * xReserve / yReserve
        tokenAmount = (msg.value * tokenReserve / ethReserve) + 1;

        uint liquidityMinted = msg.value * totalLiquidity / ethReserve;
        liquidity[msg.sender]  += liquidityMinted;
        totalLiquidity += liquidityMinted;

        require(token.transferFrom(msg.sender, address(this), tokenAmount));

        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokenAmount);

    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
     */
    function withdraw(uint256 amount) public returns (uint256 ethAmount, uint256 tokenAmount) {

        require(liquidity[msg.sender] >= amount, "Not enough Liquidity to withdraw!");

        uint ethReserve = address(this).balance;
        uint tokenReserve = token.balanceOf(address(this));

        ethAmount = amount * ethReserve / totalLiquidity;
        tokenAmount = amount * tokenReserve / totalLiquidity;

        liquidity[msg.sender] -= amount;
        totalLiquidity -= amount;

        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "Transaction failed!");

        require(token.transfer(msg.sender, tokenAmount));

        emit LiquidityRemoved(msg.sender, amount, ethAmount, tokenAmount);

    }
}