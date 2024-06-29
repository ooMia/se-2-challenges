// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDEX {
	/**
	 * @notice Contract initializer.
	 * @dev Contract deployer should call this function with the amount of LPTs and Ether they want for the initial liquidity pool.
	 * @param tokens amount of LPTs to be transferred to DEX
	 */
	function init(uint256 tokens) external payable returns (uint256);

	/**
	 * @notice Sends Ether in exchange for LPTs. The amount of LPTs is determined by the price function.
	 * @dev Make sure to exclude the amount of Ether sent while calculating the price.
	 */
	function ethToToken() external payable returns (uint256 tokenOutput);

	/**
	 * @notice Sends LPTs in exchange for Ether. The amount of Ether is determined by the price function.
	 * @dev Make sure to exclude the amount of LPTs while calculating the price if they already transferred to DEX.
	 */
	function tokenToEth(
		uint256 tokenInput
	) external returns (uint256 ethOutput);

	/**
	 * @notice allows deposits of $BAL and $ETH to liquidity pool
	 * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
	 * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
	 * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
	 */
	function deposit() external payable returns (uint256 tokensDeposited);

	/**
	 * @notice allows withdrawal of $BAL and $ETH from liquidity pool
	 */
	function withdraw(
		uint256 amount
	) external returns (uint256 eth_amount, uint256 token_amount);
}

abstract contract _DEX is IDEX {
	/**
	 * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. No modifications are allowed.
	 * @param xInput 교환하려는 입력 자산의 양
	 * @param xReserves DEX 계약에 보유된 입력 자산의 예비금
	 * @param yReserves DEX 계약에 보유된 출력 자산의 예비금
	 * @return yOutput 교환할 때의 출력 자산의 양
	 */
	function price(
		uint256 xInput,
		uint256 xReserves,
		uint256 yReserves
	) public pure returns (uint256 yOutput) {
		uint256 EXCHANGE_FEE_PER_1000 = 3; // 0.3% fee
		uint256 xInputAfterFee = xInput * (1000 - EXCHANGE_FEE_PER_1000);
		uint256 numerator = xInputAfterFee * yReserves;
		uint256 denominator = xReserves * 1000 + xInputAfterFee;
		require(denominator > 0, "division by zero");
		yOutput = numerator / denominator;
		return yOutput;
	}

	/**
	 * @notice returns liquidity of a liquidity provider.
	 */
	function getLiquidity(address lp) public view virtual returns (uint256);
}

contract DEX is _DEX {
	/* ========== GLOBAL VARIABLES ========== */

	IERC20 public token;
	uint256 public totalLiquidity; // sum of all liquidity of LPs

	address private THIS = address(this);
	mapping(address => uint256) private liquidity;
	bool private initialized;

	/* ========== EVENTS ========== */

	/**
	 * @notice Emitted when ethToToken() swap transacted
	 */
	event EthToTokenSwap(
		address swapper,
		uint256 tokenOutput,
		uint256 ethInput
	);

	/**
	 * @notice Emitted when tokenToEth() swap transacted
	 */
	event TokenToEthSwap(
		address swapper,
		uint256 tokensInput,
		uint256 ethOutput
	);

	/**
	 * @notice Emitted when liquidity provided to DEX and mints LPTs.
	 */
	event LiquidityProvided(
		address liquidityProvider,
		uint256 liquidityMinted,
		uint256 ethInput,
		uint256 tokensInput
	);

	/**
	 * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
	 */
	event LiquidityRemoved(
		address liquidityRemover,
		uint256 liquidityWithdrawn,
		uint256 tokensOutput,
		uint256 ethOutput
	);

	/* ========== MODIFIERS ========== */

	modifier positiveMessageValue() {
		require(msg.value > 0, "msg.value must be positive");
		_;
	}

	modifier positiveInteger(uint256 param) {
		require(param > 0, "param must be positive");
		_;
	}

	modifier requireLiquidity(address owner, uint256 amount) {
		require(
			liquidity[owner] >= amount,
			"require liquidity when withdrawing"
		);
		_;
	}

	modifier ratioEqualExcludeEtherReceived(uint256 eth_sent) {
		uint256 beforeRatio = getRatio(eth_sent);
		_;
		require(beforeRatio == getRatio(0), "Ratio changed");
	}

	/* ========== CONSTRUCTOR ========== */

	constructor(address token_addr) {
		token = IERC20(token_addr);
	}

	/* ========== EXTERNAL FUNCTIONS ========== */

	// deployer initializes the DEX with Ether and tokens
	// return total amount of Ether in the liquidity pool
	function init(
		uint256 tokens
	)
		external
		payable
		override
		positiveMessageValue
		positiveInteger(tokens)
		returns (uint256)
	{
		require(!initialized, "DEX already initialized");
		receiveTokenFromCaller(tokens);
		return liquidity[msg.sender] = totalLiquidity = THIS.balance;
	}

	// send Ether to DEX in exchange for tokens
	// return the amount of tokens received
	function ethToToken()
		external
		payable
		override
		positiveMessageValue
		returns (uint256 tokenOutput)
	{
		tokenOutput = exchange_ether_to_token(msg.value);
		sendTokenToCaller(tokenOutput);
		emit EthToTokenSwap(msg.sender, tokenOutput, msg.value);
		return tokenOutput;
	}

	// send tokens to DEX in exchange for Ether
	// return the amount of Ether received
	function tokenToEth(
		uint256 tokenInput
	)
		external
		override
		positiveInteger(tokenInput)
		returns (uint256 ethOutput)
	{
		receiveTokenFromCaller(tokenInput);
		ethOutput = exchange_token_to_ether(tokenInput);
		payable(msg.sender).transfer(ethOutput);
		emit TokenToEthSwap(msg.sender, tokenInput, ethOutput);
		return ethOutput;
	}

	// deposits both Ether and tokens
	// the ratio of Ether to tokens will be maintained
	// return the amount of tokens deposited
	function deposit()
		external
		payable
		override
		positiveMessageValue
		ratioEqualExcludeEtherReceived(msg.value)
		returns (uint256 tokensDeposited)
	{
		uint256 eth_amount = msg.value;
		uint256 eth_reserve = THIS.balance - eth_amount;
		addLiquidity(
			msg.sender,
			tokensDeposited = (eth_amount * totalLiquidity) / eth_reserve
		);

		uint256 token_reserve = token.balanceOf(THIS);
		uint256 token_amount = (eth_amount * token_reserve) / eth_reserve;
		receiveTokenFromCaller(token_amount);

		emit LiquidityProvided(
			msg.sender,
			tokensDeposited,
			eth_amount,
			token_amount
		);
		return tokensDeposited;
	}

	// allows withdrawal of $BAL and $ETH from liquidity pool
	// return the amount of Ether and tokens withdrawn
	function withdraw(
		uint256 amount
	)
		external
		override
		positiveInteger(amount)
		requireLiquidity(msg.sender, amount)
		ratioEqualExcludeEtherReceived(0)
		returns (uint256 eth_amount, uint256 token_amount)
	{
		uint256 eth_reserve = THIS.balance;
		eth_amount = (amount * eth_reserve) / totalLiquidity;

		uint256 token_reserve = token.balanceOf(THIS);
		token_amount = (amount * token_reserve) / totalLiquidity;

		payable(msg.sender).transfer(eth_amount);
		subLiquidity(msg.sender, eth_amount);
		sendTokenToCaller(token_amount);

		emit LiquidityRemoved(msg.sender, eth_amount, token_amount, eth_amount);
		return (eth_amount, token_amount);
	}

	/* ========== PRIVATE FUNCTIONS ========== */

	// Note: DEX contract become a msg.sender when calling functions of a token contract.
	// To reduce confusion, all interactions with the token which modify its status are handled through private functions.

	function receiveTokenFromCaller(
		uint256 amount
	) private positiveInteger(amount) {
		require(
			token.allowance(msg.sender, THIS) >= amount,
			"require allowance when receiving tokens"
		);
		token.transferFrom(msg.sender, THIS, amount);
	}

	function sendTokenToCaller(uint256 amount) private positiveInteger(amount) {
		token.transfer(msg.sender, amount);
	}

	function addLiquidity(address lp, uint256 amount) private {
		liquidity[lp] += amount;
		totalLiquidity += amount;
	}

	function subLiquidity(
		address lp,
		uint256 amount
	) private requireLiquidity(lp, amount) {
		liquidity[lp] -= amount;
		totalLiquidity -= amount;
	}

	/* ========== PRIVATE VIEW FUNCTIONS ========== */

	/**
	 * @dev assume that ether already transferred to DEX. Which means an Ether balance of DEX contract is increased by etherInput. To calculate correct price, we need to subtract etherInput from the Ether balance of DEX contract.
	 */
	function exchange_ether_to_token(
		uint256 etherInput
	) private view returns (uint256 tokenOutput) {
		return
			price(etherInput, THIS.balance - etherInput, token.balanceOf(THIS));
	}

	/**
	 * @dev assume that token already transferred to DEX. Which means a token balance of DEX contract is increased by tokenInput. To calculate correct price, we need to subtract tokenInput from the token balance of DEX contract.
	 */
	function exchange_token_to_ether(
		uint256 tokenInput
	) private view returns (uint256 etherOutput) {
		return
			price(tokenInput, token.balanceOf(THIS) - tokenInput, THIS.balance);
	}

	function getLiquidity(address lp) public view override returns (uint256) {
		return liquidity[lp];
	}

	function getRatio(uint256 eth_sent) private view returns (uint256 ratio) {
		uint256 eth_reserve = THIS.balance - eth_sent;
		uint256 token_reserve = token.balanceOf(THIS);
		ratio = eth_reserve / token_reserve;
		return ratio;
	}
}
