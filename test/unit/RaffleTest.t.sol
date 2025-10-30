// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    address private PLAYER = makeAddr("player");
    uint256 constant STARTING_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 keyHash; // gas lane
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    function setUp() external {
        (raffle, helperConfig) = new DeployRaffle().deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        keyHash = config.keyHash;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;
        vm.deal(PLAYER, STARTING_BALANCE); // give PLAYER some ETH
    }

    function testRaffleInitialization() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        assert(raffle.getInterval() == interval);
    }

    /** ENTER RAFFLE TESTS STARTS HERE ------------> */

    function testEnterRaffleRevertsOnNotEnoughETH() public {
        vm.expectRevert(Raffle.Raffle__NotEnoughETHSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerOnEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEventEmitsOnEnter() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle)); // ref: https://getfoundry.sh/reference/cheatcodes/expect-emit/
        emit Raffle.RaffleEnter(PLAYER); // this event is expected

        // above lines set the expectation for the event, below line should cause the event to be emitted
        raffle.enterRaffle{value: entranceFee}();
    }

    modifier raffleEnter() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Simulate that the raffle is in CALCULATING state
        vm.warp(block.timestamp + interval + 1); // update the timestamp
        vm.roll(block.number + 1); // update the block
        _;
    }

    function testEnterRaffleRevertsOnRaffleNotOpen() public raffleEnter {
        raffle.performUpkeep(""); // call performUpkeep

        vm.expectRevert(Raffle.Raffle__NotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /** CHECK UPKEEP TESTS STARTS HERE ------------> */

    function testCheckUpkeepReturnsFalseIfNoPlayers() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1); // update the timestamp
        vm.roll(block.number + 1); // update the block

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckupKeepReturnsFalseIfRaffleNotOpen() public raffleEnter {
        raffle.performUpkeep(""); // call performUpkeep to change state to CALCULATING

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfNotEnoughTimeHasPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval - 10); // update the timestamp
        vm.roll(block.number + 1); // update the block

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenConditionsMet() public raffleEnter {
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    /** PERFORM UPKEEP TESTS STARTS HERE ------------> */

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue()
        public
        raffleEnter
    {
        // Act / Assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 balance = 0;
        uint256 numPlayers = 0;

        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        balance += entranceFee;
        numPlayers += 1;

        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                raffle.getRaffleState(),
                numPlayers,
                balance,
                (block.timestamp - raffle.getLastTimeStamp())
            )
        );
        raffle.performUpkeep("");
    }

    /** FULLFILL RANDOM WORDS TESTS STARTS HERE ------------> */

    function testFullfillRamdomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 requestId // using this requestId to simulate the requestId generated in performUpkeep, populated by foundry itself, known as fuzz testing
    ) public raffleEnter {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            requestId,
            address(raffle)
        );
    }

    function testFullfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnter
    {
        // Arrange
        uint256 startingIndex = 1;
        uint256 additionalPlayers = 3; // total 4 players including initial PLAYER

        for (uint8 i = startingIndex; i <= additionalPlayers; i++) {
            address newPlayer = address(uint160(PLAYER) + i); // create new address by incrementing PLAYER address
            hoax(newPlayer, 1 ether); // pranks newPlayer and gives 1 ether
            raffle.enterRaffle{value: entranceFee}(); // newPlayer enters the raffle
        }

        uint256 prize = entranceFee * (additionalPlayers + 1); // total players = additionalPlayers + initial PLAYER

        // Act
        vm.recordLogs(); // start recording logs
        raffle.performUpkeep(""); // this will kick off the random winner selection
        Vm.Log[] memory entries = vm.getRecordedLogs(); // get all recorded logs
        bytes32 requestId = entries[1].topics[1]; // get the requestId from the second log (first log is for performUpkeep)

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        assert(raffle.getRecentWinner() == PLAYER);
        assert(raffle.getBalance() == 0);
        assert(raffle.getLastTimeStamp() == block.timestamp);
    }
}
