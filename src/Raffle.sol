// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle
 * @author Prakash Banjade
 * @notice A simple raffle contract
 * @dev Implements Chainlink VRF v2.5 for randomness
 * @dev For chainlink VRF contract variables -> https://docs.chain.link/vrf/v2-5/getting-started#contract-variables
 */
contract Raffle is VRFConsumerBaseV2Plus {
    // ERRORS
    error Raffle__NotEnoughETHSent();
    error Raffle__IntervalNotPassed();
    error Raffle__TransferFailed();
    error Raffle__NotOpen();
    error Raffle__UpkeepNotNeeded(
        RaffleState currentState,
        uint256 numPlayers,
        uint256 contractBalance,
        uint256 timeSinceLastWinner
    );

    uint8 private constant REQUEST_CONFIRMATIONS = 3;
    uint8 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; // interval between raffle winner
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private lastTimeStamp;
    address payable private recentWinner;

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    RaffleState private s_state = RaffleState.OPEN;

    /** EVENTS */
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed winner);
    event RaffleWinnerPicked(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 keyHash, // gas lane
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        lastTimeStamp = block.timestamp; // immediately set the timestamp when deployed
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) revert Raffle__NotEnoughETHSent();
        if (s_state != RaffleState.OPEN) revert Raffle__NotOpen();

        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    /**
     * @notice This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return true.
     * The following should be true in order to return true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is open
     * 3. The contract has ETH
     * 4. Implicitly, we need at least 1 player
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool isOpen = (s_state == RaffleState.OPEN);
        bool timePassed = ((block.timestamp - lastTimeStamp) >= i_interval);
        bool hasPlayers = (s_players.length > 0);
        bool hasBalance = (address(this).balance > 0);
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
        return (upkeepNeeded, bytes(""));
    }

    /**
     * @notice This function is called by the Chainlink Keeper nodes
     * when `checkUpkeep` returns true.
     * The following does:
     * 1. Sets the raffle state to calculating
     * 2. Calls the VRF coordinator to get random numbers
     * 3. The VRF coordinator then calls `fulfillRandomWords`
     */
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded)
            revert Raffle__UpkeepNotNeeded(
                s_state,
                s_players.length,
                address(this).balance,
                (block.timestamp - lastTimeStamp)
            );

        s_state = RaffleState.CALCULATING;
        // this now actually makes the request to the VRF coordinator, after completion, it internally calls `rawFulfillRandomWords`
        // which then calls `fulfillRandomWords` defined below
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        emit RaffleWinnerPicked(requestId);
    }

    /**
     * @notice This function is called by the VRF Coordinator when it receives a valid VRF proof.
     * @dev This function must be implemented by the contract that inherits from VRFConsumerBase
     */
    function fulfillRandomWords(
        uint256, // no variable name means we won't use this parameter
        uint256[] calldata randomWords
    ) internal override {
        // randomWords is an array of random words, we requested only 1 word, so it will be at index 0,
        // eg. [838208912300013333]
        uint256 indexOfWinner = randomWords[0] % s_players.length; // modulo to get index within range
        recentWinner = s_players[indexOfWinner];

        // reset
        s_players = new address payable[](0);
        lastTimeStamp = block.timestamp;
        s_state = RaffleState.OPEN;

        // send the money to the winner
        (bool ok, ) = recentWinner.call{value: address(this).balance}("");
        if (!ok) revert Raffle__TransferFailed();

        // emit event
        emit WinnerPicked(recentWinner);
    }

    /** Getters */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return lastTimeStamp; 
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getRecentWinner() external view returns (address) {
        return recentWinner;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_state;
    }
}
