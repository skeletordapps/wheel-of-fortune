// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// imports
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract WheelV2 is VRFConsumerBaseV2 {
  uint256 public immutable entryFee = 0.01 ether;
  uint256 public immutable spinFee = 0.001 ether;
  address public immutable MULTISIG;

  /// Chainlink VRF
  VRFCoordinatorV2Interface COORDINATOR;
  address coordinatorAddress = 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D;
  uint64 subscriptionId;
  bytes32 keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;
  uint32 callbackGasLimit = 100000;
  uint16 requestConfirmations = 3;
  uint32 numWords = 2;
  uint256[] public requestIds;
  uint256 public lastRequestId;
  mapping(uint256 => RequestStatus) public requests;
  /// -----------------------------------------------------------------------------------

  uint256[] public weights = [10, 6, 8, 6, 3, 2, 30, 20, 10, 5];
  mapping(address => uint256) public balances;
  mapping(address => uint256) public prizes;

  enum WheelPrize {
    FREESPIN,
    X2,
    WIN5,
    WIN10,
    WIN20,
    WIN30,
    LOSE2,
    LOSE3,
    LOSE5,
    LOSEALL
  }

  struct RequestStatus {
    bool fulfilled;
    bool exists;
    uint256[] randomWords;
  }

  event Entered(address indexed, uint256);
  event Withdrawn(address indexed, uint256);
  event Delivered(address indexed, WheelPrize);
  event PrizeRequested(address indexed, uint256 requestId, uint32 numWords);
  event PrizeFulfilled(uint256 requestId, uint256[] randomWords);

  error Levi_Wheel_Insufficient_Ether();
  error Levi_Wheel_Insufficient_Balance();

  constructor(uint64 _subscriptionId, address _multisign) VRFConsumerBaseV2(coordinatorAddress) {
    subscriptionId = _subscriptionId;
    MULTISIG = _multisign;
    COORDINATOR = VRFCoordinatorV2Interface((coordinatorAddress));
  }

  function enter() external payable {
    if (msg.value < entryFee) revert Levi_Wheel_Insufficient_Ether();
    balances[msg.sender] = msg.value;

    emit Entered(msg.sender, msg.value);
  }

  function spin() external {
    if (balances[msg.sender] < spinFee) revert Levi_Wheel_Insufficient_Balance();
    balances[msg.sender] -= spinFee;

    uint256 requestId = COORDINATOR.requestRandomWords(
      keyHash,
      subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      numWords
    );

    requests[requestId] = RequestStatus({
      randomWords: new uint256[](0),
      exists: true,
      fulfilled: false
    });

    requestIds.push(requestId);
    lastRequestId = requestId;
    emit PrizeRequested(msg.sender, requestId, numWords);
  }

  function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
    require(requests[_requestId].exists, "request not found");
    requests[_requestId].fulfilled = true;
    requests[_requestId].randomWords = _randomWords;
    emit PrizeFulfilled(_requestId, _randomWords);

    uint256 pickedPrize = pickPositionByWeight(weights, _randomWords[0]);
    deliver(WheelPrize(pickedPrize));
  }

  function deliver(WheelPrize prize) internal {
    if (prize == WheelPrize.FREESPIN) balances[msg.sender] += spinFee;
    if (prize == WheelPrize.X2) prizes[msg.sender] = balances[msg.sender] * 2;
    if (prize == WheelPrize.WIN5) prizes[msg.sender] = spinFee * 5;
    if (prize == WheelPrize.WIN10) prizes[msg.sender] = spinFee * 10;
    if (prize == WheelPrize.WIN20) prizes[msg.sender] = spinFee * 20;
    if (prize == WheelPrize.WIN30) prizes[msg.sender] = spinFee * 30;
    if (prize == WheelPrize.LOSE2) {
      if (balances[msg.sender] >= spinFee * 2) {
        balances[msg.sender] -= spinFee * 2;
      } else {
        balances[msg.sender] = 0;
      }
    }
    if (prize == WheelPrize.LOSE3) {
      if (balances[msg.sender] >= spinFee * 3) {
        balances[msg.sender] -= spinFee * 3;
      } else {
        balances[msg.sender] = 0;
      }
    }

    if (prize == WheelPrize.LOSE5) {
      if (balances[msg.sender] >= spinFee * 5) {
        balances[msg.sender] -= spinFee * 5;
      } else {
        balances[msg.sender] = 0;
      }
    }

    if (prize == WheelPrize.LOSEALL) balances[msg.sender] = 0;

    emit Delivered(msg.sender, prize);
  }

  function withdraw() external {
    uint256 balance = balances[msg.sender];
    balances[msg.sender] = 0;

    (bool success, ) = msg.sender.call{value: balance}("");
    require(success);

    emit Withdrawn(msg.sender, balance);
  }

  /**
   * @notice Pick a prize based on weights
   * @dev This func uses a math formula
   */
  function pickPositionByWeight(
    uint256[] memory choiceWeight,
    uint256 randomNumber
  ) internal pure returns (uint256) {
    uint256 sum_of_weight = 0;
    for (uint256 i = 0; i < choiceWeight.length; i++) {
      sum_of_weight += choiceWeight[i];
    }
    uint256 rnd = randomNumber % sum_of_weight;
    for (uint256 i = 0; i < choiceWeight.length; i++) {
      if (rnd < choiceWeight[i]) return i;
      rnd -= choiceWeight[i];
    }
    return rnd;
  }

  receive() external payable {}
}
