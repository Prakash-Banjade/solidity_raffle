// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

error Raffle__NotEnoughETHSent();
error Raffle__IntervalNotPassed();
error Raffle__TransferFailed();

/**
 * @title Raffle
 * @author Prakash Banjade
 * @notice A simple raffle contract
 * @dev Implements Chainlink VRF v2.5 for randomness
 * @dev For chainlink VRF contract variables -> https://docs.chain.link/vrf/v2-5/getting-started#contract-variables
 */
contract Raffle is VRFConsumerBaseV2Plus {
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

    /** EVENTS */
    event RaffleEnter(address indexed player);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 keyHash,
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

        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    /**
        1. Get a random number
        2. Use the random number to pick a winner
        3. Automatically be triggered after each i_interval
        4. Send the money to the winner
     */
    function pickWinner() public {
        // check if enough time has passed
        if (block.timestamp - lastTimeStamp < i_interval)
            revert Raffle__IntervalNotPassed();

        // this now actually makes the request to the VRF coordinator, after completion, it internally calls `rawFulfillRandomWords`
        // which then calls `fulfillRandomWords` defined below
        s_vrfCoordinator.requestRandomWords(
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
    }

    /**
     * @notice This function is called by the VRF Coordinator when it receives a valid VRF proof.
     * @dev This function must be implemented by the contract that inherits from VRFConsumerBase
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        // randomWords is an array of random words, we requested only 1 word, so it will be at index 0,
        // eg. [838208912300013333]
        uint256 indexOfWinner = randomWords[0] % s_players.length; // modulo to get index within range
        recentWinner = s_players[indexOfWinner];

        // send the money to the winner
        (bool ok, ) = recentWinner.call{value: address(this).balance}("");
        if (!ok) revert Raffle__TransferFailed();
    }

    /** Getters */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }
}
