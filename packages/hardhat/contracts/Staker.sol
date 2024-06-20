// SPDX-License-Identifier: MIT
pragma solidity 0.8.4; //Do not change the solidity version as it negativly impacts submission grading

// +--------+
// | import |
// +--------+

// import "hardhat/console.sol";
import "./ExampleExternalContract.sol";

// +-----------+
// | interface |
// +-----------+

interface IStaker {
	// +---------------------+
	// | Function (external) |
	// +---------------------+

	// Receives eth and calls stake()
	receive() external payable;

	// After some `deadline` allow anyone to call an `execute()` function, just once
	// If the deadline has passed and the threshold is met
	// It should call `exampleExternalContract.complete{value: address(this).balance}()`
	function execute() external;

	// If the deadline has passed and the `threshold` was not met,
	// allow everyone to call a `withdraw()` function to withdraw their balance
	function withdraw() external;
}

abstract contract _Staker is IStaker {
	// +-------------------+
	// | Function (public) |
	// +-------------------+

	// Collect funds in a payable `stake()` function and track individual `balances` with a mapping:
	// Make sure to emit `Stake(address,uint256)` event for the frontend `All Stakings` tab to display
	function stake() public payable virtual;

	// Add a `timeLeft()` view function that returns the time left before the deadline for the frontend
	function timeLeft() public view virtual returns (uint256);
}

contract Staker is _Staker {
	// +----------------+
	// | State Variable |
	// +----------------+

	ExampleExternalContract public exampleExternalContract;

	mapping(address => uint256) public balances;
	uint256 public threshold;
	uint256 public deadline;

	bool private openForWithdraw;

	// +-------+
	// | Event |
	// +-------+

	// Make sure to add a `Stake(address,uint256)` event and emit it for the frontend `All Stakings` tab to display)
	event Stake(address indexed staker, uint256 amount);

	// +-------+
	// | Error |
	// +-------+

	error ShouldStakeMoreThanZero();

	// +----------+
	// | Modifier |
	// +----------+

	modifier onProceed() {
		require(!exampleExternalContract.completed(), "Staking completed");
		_;
	}

	modifier onTimeOut() {
		require(isTimeOut(), "Wait for the contract to complete");
		_;
	}

	// +-----------------------+
	// | Function (implements) |
	// +-----------------------+

	constructor(address exampleExternalContractAddress) {
		exampleExternalContract = ExampleExternalContract(
			exampleExternalContractAddress
		);
		threshold = 0.0011 ether;
		deadline = block.timestamp + 5 minutes;
	}

	receive() external payable override {
		stake();
	}

	function execute() external override onProceed onTimeOut {
		if (!openForWithdraw && isThresholdMet()) {
			exampleExternalContract.complete{ value: address(this).balance }();
		}
		openForWithdraw = true;
	}

	function withdraw() external override onTimeOut {
		require(openForWithdraw, "Run Execute first");
		uint256 amount = balances[msg.sender];
		if (amount <= 0) revert ShouldStakeMoreThanZero();
		balances[msg.sender] = 0;
		payable(msg.sender).transfer(amount);
	}

	function stake() public payable override onProceed {
		if (msg.value <= 0) revert ShouldStakeMoreThanZero();
		balances[msg.sender] += msg.value;
		emit Stake(msg.sender, msg.value);
	}

	function timeLeft() public view override returns (uint256) {
		if (block.timestamp >= deadline) {
			return 0;
		}
		return deadline - block.timestamp;
	}

	// +--------------------+
	// | Function (private) |
	// +--------------------+

	function isTimeOut() private view returns (bool) {
		return timeLeft() == 0;
	}

	function isThresholdMet() private view returns (bool) {
		return address(this).balance >= threshold;
	}
}
