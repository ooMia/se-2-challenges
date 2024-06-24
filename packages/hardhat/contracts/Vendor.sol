pragma solidity 0.8.4; //Do not change the solidity version as it negativly impacts submission grading
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "./YourToken.sol";

interface IVendor {
	function buyTokens() external payable;

	function withdraw() external;

	function sellTokens(uint256 _amount) external;
}

contract Vendor is IVendor, Ownable {
	event BuyTokens(address buyer, uint256 amountOfETH, uint256 amountOfTokens);
	event SellTokens(
		address seller,
		uint256 amountOfTokens,
		uint256 amountOfETH
	);

	YourToken public yourToken;

	constructor(address tokenAddress) {
		yourToken = YourToken(tokenAddress);
	}

	function buyTokens() external payable override {
		uint256 amountOfTokens = msg.value * tokensPerEth();
		yourToken.transfer(msg.sender, amountOfTokens);
		emit BuyTokens(msg.sender, msg.value, amountOfTokens);
	}

	function withdraw() external override {
		require(msg.sender == owner(), "Only the owner can withdraw");
		payable(owner()).transfer(address(this).balance);
	}

	function sellTokens(uint256 _amount) external override {
		yourToken.transferFrom(msg.sender, address(this), _amount);
		uint256 amountOfTokens = _amount / tokensPerEth();
		payable(msg.sender).transfer(amountOfTokens);
		emit SellTokens(msg.sender, _amount, amountOfTokens);
	}

	function tokensPerEth() public pure returns (uint256) {
		return 100;
	}
}
