//SPDX License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployDSC} from "../script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "lib/openzepplin-contracts/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethusdPriceFeed;
        address wbtcusdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerkey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE_FEED = 2000e8;
    int256 public constant BTC_USD_PRICE_FEED = 1000e8;
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff8;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            wethusdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcusdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wbtc: 0xE47dE7c2c4d24198Ff8f3bC3a1d3C529c67925BD,
            deployerkey: DEFAULT_ANVIL_KEY
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethusdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE_FEED);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE_FEED);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        return NetworkConfig({
            wethusdPriceFeed: address(ethUsdPriceFeed),
            wbtcusdPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerkey: DEFAULT_ANVIL_KEY
        });
    }
}
