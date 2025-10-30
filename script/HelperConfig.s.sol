// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    // VRFCoordinatorV2_5Mock Parameters
    uint96 constant BASE_FEE = 0.1 ether;
    uint96 constant GAS_PRICE_LINK = 1e9;
    int256 constant WEI_PER_UNIT_LINK = 1e18; // LINK / ETH price

    address public constant FOUNDRY_DEFAULT_SENDER =
        0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant MAINNET_CHAIN_ID = 1;
    uint256 public constant ANVIL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__NoNetworkConfig();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 keyHash;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address link;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigs[MAINNET_CHAIN_ID] = getMainNetEthConfig();
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 300,
                vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B, // ref: https://docs.chain.link/vrf/v2-5/supported-networks#ethereum
                keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, // 500 gwei gas lane, ref: same as vrfCoordinator link above
                subscriptionId: 17539377725174599888276367515352997736388966812528430757343731333584813194614, // need to create in https://vrf.chain.link/sepolia
                callbackGasLimit: 200_000, // 200,000 gas
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789 // ref: https://docs.chain.link/resources/link-token-contracts#sepolia-testnet
            });
    }

    function getMainNetEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.1 ether,
                interval: 300,
                vrfCoordinator: 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a,
                keyHash: 0x8077df514608a09f83e4e8d300645594e5d7234665448ba83f51a50f842bd3d9, // 200 wei gas lane
                subscriptionId: 0, // need to use a valid one
                callbackGasLimit: 200_000, // 200,000 gas
                link: 0x514910771AF9Ca656af840dff83E8264EcF986CA
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // If we have a vrfCoordinator address, we already created one
        if (localNetworkConfig.vrfCoordinator != address(0)) {
            return localNetworkConfig;
        }

        /**
            Since, the local network doesn't have VRF coordinator, we have to create and deploy a mock
         */
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrf = new VRFCoordinatorV2_5Mock( // `vrf` is the address of the mock deployed
            BASE_FEE,
            GAS_PRICE_LINK,
            WEI_PER_UNIT_LINK
        );

        LinkToken link = new LinkToken();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 300,
            vrfCoordinator: address(vrf), // address of the mock deployed
            keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, // 500 gwei gas lane, doesn't matter for local network
            subscriptionId: 0,
            callbackGasLimit: 200_000, // 200,000 gas
            link: address(link)
        });

        return localNetworkConfig;
    }

    function getNetworkConfigByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        NetworkConfig memory config = networkConfigs[chainId];

        if (config.vrfCoordinator != address(0)) return config;
        if (chainId == ANVIL_CHAIN_ID) return getOrCreateAnvilEthConfig();

        revert HelperConfig__NoNetworkConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getNetworkConfigByChainId(block.chainid);
    }

    function run() external returns (address) {}
}
