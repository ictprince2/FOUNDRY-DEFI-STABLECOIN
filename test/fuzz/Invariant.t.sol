// SPDX License_Identifier: MIT

//what are a invariants?

// the total supply of DSC should always be less than the value of the collatral value

// our getter view function should never revert -> evergreen invariants

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "lib/openzepplin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invaraint is StdInvariant, Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    Handler handler;

    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();

        handler = new Handler(engine, dsc);

        targetContract(address(handler));
    }

    function invariant__protocolMustHaveValueThanTotalSupply() public view {
        // get the value of all the collateral value in the protocol
        // comapare them with the debt or the DSC
        uint256 totalSupply = dsc.totalSupply();

        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("wethValue", wethValue);
        console.log("wbtcValue", wbtcValue);
        console.log("totalSupply", totalSupply);
        console.log("time mint is called:", handler.timeMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    //  fucntion Invaraint__gettersShouldNotRevert () public {}
}
