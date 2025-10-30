// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DeployRaffle is Script {
    function run() external {
        deployContract();
    }

    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        /**
            if we don't have a subscription, create one then fund it, then assign the subscriptionId to the config
         */
        if (config.subscriptionId == 0) {
            // create subscription
            CreateSubscription subscription = new CreateSubscription();
            config.subscriptionId = subscription.create(config.vrfCoordinator);

            // fund subscription
            FundSubscription funder = new FundSubscription();
            funder.fund(
                config.vrfCoordinator,
                config.subscriptionId,
                config.link
            );
        }

        /**
            deploy contract
         */
        vm.startBroadcast();

        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.keyHash,
            config.subscriptionId,
            config.callbackGasLimit
        );

        vm.stopBroadcast();

        /**
            add consumer
         */
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.add(
            config.vrfCoordinator,
            config.subscriptionId,
            address(raffle)
        );

        return (raffle, helperConfig);
    }
}
