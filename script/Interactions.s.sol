// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function createSubscription() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subId = create(vrfCoordinator);

        return (subId, vrfCoordinator);
    }

    function create(address vrfCoordinator) public returns (uint256) {
        console.log("Creating subscription on VRFCoordinator:", vrfCoordinator);
        vm.startBroadcast();
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();

        return subId;
    }

    function run() external {
        createSubscription();
    }
}

/**
    @notice This script can fund a VRF subscription programmatically for the given VRFCoordinator and subscriptionId.
    It handles both local Anvil networks (using VRFCoordinatorV2_5Mock) and real networks (using LinkToken transferAndCall).
    @dev Make sure to set the correct network configuration in HelperConfig before running this script.
 */
contract FundSubscription is Script, CodeConstants {
    uint256 constant FUND_AMOUNT = 2 ether; // 2 LINK

    function fundSubscription() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address linkToken = helperConfig.getConfig().link;

        fund(vrfCoordinator, subscriptionId, linkToken);
    }

    function fund(
        address vrfCoordinator,
        uint256 subscriptionId,
        address link
    ) public {
        console.log("Funding subscription on VRFCoordinator:", vrfCoordinator);

        if (block.chainid == CodeConstants.ANVIL_CHAIN_ID) {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(
                subscriptionId,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            LinkToken(link).transferAndCall(
                vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subscriptionId)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscription();
    }
}

contract AddConsumer is Script {
    function addConsumer(address consumer) internal {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;

        add(vrfCoordinator, subscriptionId, consumer);
    }

    function add(
        address vrfCoordinator,
        uint256 subscriptionId,
        address consumer // address of the contract to be added as consumer
    ) public {
        console.log(
            "Adding consumer %s to subscription on VRFCoordinator %s",
            consumer,
            vrfCoordinator
        );
        // adding consumer to either local or real network has the same process and ABI signature, so no need to differentiate
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(
            subscriptionId,
            consumer
        );
        vm.stopBroadcast();
    }

    function run() external {
        address mostRecentDeployed = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addConsumer(mostRecentDeployed);
    }
}
