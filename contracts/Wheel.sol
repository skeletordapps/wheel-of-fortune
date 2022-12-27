// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// imports
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

/**
 * @notice Functions helper
 */
library WheelHelper {
  /**
   * @notice Pick a prize based on weights
   * @dev This func uses a math formula
   */
  function pickPositionByWeight(
    uint256 numChoices,
    uint256[] memory choiceWeight,
    uint256 randomNumber
  ) internal pure returns (uint256) {
    uint256 sum_of_weight = 0;
    for (uint256 i = 0; i < numChoices; i++) {
      sum_of_weight += choiceWeight[i];
    }
    uint256 rnd = randomNumber % sum_of_weight;
    for (uint256 i = 0; i < numChoices; i++) {
      if (rnd < choiceWeight[i]) return i;
      rnd -= choiceWeight[i];
    }
    return rnd;
  }

  /**
   * @notice Send Transaction
   * @dev Transfer money from contract to player
   */
  function sendPrize(address payable playerAddress, uint256 prizeAmount) internal {
    (bool success, ) = playerAddress.call{value: prizeAmount}("");
    if (!success) {
      revert Wheel__TransferFailed();
    }
  }
}

// errors
error Wheel__NotEnoughToEnter();
error Wheel__PlayerNoBalance();
error Wheel__NoBalance();
error Wheel__NotOpen();
error Wheel__NotEntered();
error Wheel__TransferFailed();
error Wheel__NothingToClaim();

/** @title Wheel of fortune contract
 * @author 0xL
 * @notice This manages a decentralized wheel of fortune game
 * @dev This contract implements Chainlink VRF to pick the wheel prize position
 */

contract Wheel is Ownable {
  // types
  enum WheelState {
    IDDLE,
    OPEN,
    CLOSED
  }

  enum PlayerState {
    READY,
    SPINING,
    UNBALANCED
  }

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

  uint256 public immutable enterFee = 0.01 ether;
  uint256 public immutable spinFee = 0.001 ether;
  uint256 public immutable minBalance = 0.01 ether * 10;

  uint256 public playersCount;
  uint256[] public prizesWeight = [10, 6, 8, 6, 3, 2, 30, 20, 10, 5];
  string[] public prizes = [
    "FREESPIN",
    "X2",
    "WIN5",
    "WIN10",
    "WIN20",
    "WIN30",
    "LOSE2",
    "LOSE3",
    "LOSE5",
    "LOSEALL"
  ];
  mapping(address => Player) public addressToPlayer;
  mapping(address => uint256) public addressToPrize;
  WheelState public state;

  // structs
  struct Player {
    uint256 balance;
    PlayerState state;
    WheelPrize lastPrize;
  }

  // events
  event WheelIsOpen();
  event WheelEnter(address indexed player);
  event WheelRequestedNumber(uint256 indexed requestId);
  event WheelPrizeSent(address indexed player, WheelPrize indexed prize);
  event WheelClosed();
  event WheelZeroBalance();
  event WheelFilled(address indexed owner, uint256 amount);
  event WheelPrizeClaimed(address indexed player, uint256 prize);

  // chainlink
  event RequestSent(uint256 requestId, uint32 numWords);
  event RequestFulfilled(uint256 requestId, uint256[] randomWords);

  modifier onlyWhenCanEnter() {
    if (state != WheelState.OPEN) {
      revert Wheel__NotOpen();
    }

    if (msg.value < enterFee) {
      revert Wheel__NotEnoughToEnter();
    }
    _;
  }

  modifier onlyWhenCanSpin() {
    if (state != WheelState.OPEN) {
      revert Wheel__NotOpen();
    }

    if (addressToPlayer[msg.sender].balance < spinFee) {
      revert Wheel__PlayerNoBalance();
    }
    _;
  }

  modifier onlyWhenCanClaim() {
    if (addressToPrize[msg.sender] == 0) {
      revert Wheel__NothingToClaim();
    }
    _;
  }

  constructor() payable {
    state = WheelState.IDDLE;
  }

  // Payable functions

  /**
   * @notice Player enters the wheel
   * @dev Set player in mapping and updates players counter
   */
  function enter() public payable onlyWhenCanEnter {
    addressToPlayer[msg.sender] = Player(enterFee, PlayerState.READY, WheelPrize.LOSE2);
    playersCount++;
    emit WheelEnter(msg.sender);
  }

  /**
   * @dev Get a random number
   */
  function random() private view returns (uint256) {
    return uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, msg.sender)));
  }

  /**
   * @notice Player spins the wheel
   * @dev Reduce players balance/state
   */
  function spin() public payable onlyWhenCanSpin {
    addressToPlayer[msg.sender].state = PlayerState.SPINING;
    addressToPlayer[msg.sender].balance -= spinFee;
    uint256 pickedPrize = WheelHelper.pickPositionByWeight(prizes.length, prizesWeight, random());
    deliveryPrize(payable(msg.sender), WheelPrize(pickedPrize));
  }

  /**
   * @notice Delivers the player's prize
   * @dev Check picked random prize and deliver prize to player's pool
   */
  function deliveryPrize(address payable playerAddress, WheelPrize prize) internal {
    Player memory player = addressToPlayer[playerAddress];

    if (prize == WheelPrize.FREESPIN) {
      player.balance += spinFee;
    } else if (prize == WheelPrize.X2) {
      addressToPrize[playerAddress] = player.balance * 2;
    } else if (prize == WheelPrize.WIN5) {
      addressToPrize[playerAddress] = spinFee * 5;
    } else if (prize == WheelPrize.WIN10) {
      addressToPrize[playerAddress] = spinFee * 10;
    } else if (prize == WheelPrize.WIN20) {
      addressToPrize[playerAddress] = spinFee * 20;
    } else if (prize == WheelPrize.WIN30) {
      addressToPrize[playerAddress] = spinFee * 30;
    } else if (prize == WheelPrize.LOSE2) {
      if (player.balance >= spinFee * 2) {
        player.balance -= spinFee * 2;
      } else {
        player.balance = 0;
      }
    } else if (prize == WheelPrize.LOSE3) {
      if (player.balance >= spinFee * 3) {
        player.balance -= spinFee * 3;
      } else {
        player.balance = 0;
      }
    } else if (prize == WheelPrize.LOSE5) {
      if (player.balance >= spinFee * 5) {
        player.balance -= spinFee * 5;
      } else {
        player.balance = 0;
      }
    } else if (prize == WheelPrize.LOSEALL) {
      player.balance = 0;
    }

    if (player.balance == 0) {
      player.state = PlayerState.UNBALANCED;
    }
    player.lastPrize = prize;

    if (player.state == PlayerState.SPINING) {
      player.state = PlayerState.READY;
    }

    addressToPlayer[playerAddress] = player;
    emit WheelPrizeSent(playerAddress, prize);
  }

  function claim(address payable _player) external onlyWhenCanClaim {
    uint256 prize = addressToPrize[_player];
    addressToPrize[_player] = 0;
    WheelHelper.sendPrize(_player, prize);
    emit WheelPrizeClaimed(_player, prize);
  }

  // close wheel and withdraw remaning funds
  /**
   * @notice Owner closes the wheel
   * @dev Updates wheel state to CLOSED and withdraw all funds to owner
   */
  function withdraw() public onlyOwner {
    state = WheelState.CLOSED;
    uint256 balance = address(this).balance;
    if (balance == 0) {
      emit WheelZeroBalance();
    }
    if (balance > 0) {
      (bool success, ) = owner().call{value: address(this).balance}("");
      if (!success) {
        revert Wheel__TransferFailed();
      }
    }
    emit WheelClosed();
  }

  // view functions

  function getBalance() public view returns (uint256) {
    return address(this).balance;
  }

  // fallback
  receive() external payable onlyOwner {
    if (msg.value >= minBalance) {
      state = WheelState.OPEN;
      emit WheelIsOpen();
    }

    emit WheelFilled(owner(), msg.value);
  }
}
