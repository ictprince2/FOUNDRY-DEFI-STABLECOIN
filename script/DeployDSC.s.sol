//SPDX License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address wethusdPriceFeed, address wbtcusdPriceFeed, address weth, address wbtc, uint256 deployerkey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethusdPriceFeed, wbtcusdPriceFeed];

        vm.startBroadcast(deployerkey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (dsc, engine, config);
    }
}
