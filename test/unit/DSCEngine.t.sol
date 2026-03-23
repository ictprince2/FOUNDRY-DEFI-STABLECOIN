//SPDX License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzepplin-contracts/contracts/mocks/ERC20Mock.sol"; //updAated mock location
// import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
// import {MockMoreDebtDSC} from "../../mocks/MockMoreDebtDSC.sol";
// import {MockFailedMintDSC} from "../../mocks/MockFailedMintDSC.sol";
// import {MockFailedTransferFrom} from "../../mocks/MockFailedTransferFrom.sol";
// import {MockFailedTransfer} from "../../mocks/MockFailedTransfer.sol";
// import {Test, console} from "forge-std/Test.sol";
// import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCEngineTest is Test {
    event collateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    ); // if  redeemFrom != redeemedTo, then it was liquidated

    DecentralizedStableCoin dsc;
    HelperConfig config;
    DSCEngine engine;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;

    address public user = address(1);

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;
    // function setUp() public {
    //     deployer = new DeployDSC();
    //     (dsc, engine, config) = deployer.run();
    //     (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc  , ) = config
    //         .activeNetworkConfig();

    //     ERC20Mock(weth).mint(USER, STARTING_ERC20_BALACNE);
    // }

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        // if (block.chainid == 31_337) {
        //     vm.deal(user, STARTING_USER_BALANCE);
        // }
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
    }
    ////////////////////////
    // CONSTRUCTURE TESTS //
    ////////////////////////
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertIfTokenAddressDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);

        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__tokenAddressesAndpriceFeedsAddresssesMustHaveTheSameLenght.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////
    // PRICE FEED TESTS //
    /////////////////////
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsdValue = 30000e18; // 1500 * 2000 (ETH/USD price feed) = 30000 USD
        uint256 actualUsdValue = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsdValue, actualUsdValue);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $2000 / ETH , $100 = ?? ETH ?? 100 / 2000 = 0.05

        uint256 expectedWethValue = 0.05 ether;
        uint256 actualWethValue = engine.getCollateralAmountToLiquidate(weth, usdAmount);
        assertEq(expectedWethValue, actualWethValue);
    }

    ///////////////////////////////
    //  DEPOSIT COLLATERAL TESTS //
    //////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral); //approve token can go to the protocol

        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfTokenIsNotAllowed() public {
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", user, amountCollateral);
        vm.startBroadcast(user);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);

        engine.depositCollateral(address(randomToken), amountCollateral);
        vm.stopBroadcast();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);

        engine.depositCollateral(weth, amountCollateral);

        vm.stopPrank();

        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDSCMinted, uint256 CollateralValueInUsd) = engine.getAccountInformation(user);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getUsdValue(weth, amountCollateral);

        assertEq(totalDSCMinted, expectedTotalDscMinted);

        assertEq(CollateralValueInUsd, expectedDepositAmount);
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    // function testRevertsIfMintedDscBreaksHealthFactor() public {
    //     (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
    //     amountToMint =
    //         (amountCollateral * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();
    //     vm.startPrank(user);
    //     ERC20Mock(weth).approve(address(engine), amountCollateral);

    //     uint256 expectedHealthFactor =
    //         engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, amountCollateral));
    //     vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
    //     engine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
    //     vm.stopPrank();
    // }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositColleteralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositColleteralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.mintDSCToken(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(user);
        engine.mintDSCToken(amountToMint);

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositColleteralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        engine.burnDSC(0);
        vm.stopPrank();
    }

    function testCannotMintWithoutDepositingCollateral() public {
        vm.startPrank(user);

        // Do NOT deposit collateral; do NOT approve anything.
        // Try to mint — should revert because health factor will be broken.
        // With 0 collateral, the health factor will be 0
        uint256 expectedHealthFactor = engine.calculateHealthFactor(amountToMint, 0);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDSCToken(amountToMint);

        vm.stopPrank();
    }

    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        uint256 userBalanceBeforeRedeem = engine.getCollateralBalanceOfUser(user, weth);
        assertEq(userBalanceBeforeRedeem, amountCollateral);
        engine.redeemCollateral(weth, amountCollateral);
        uint256 userBalanceAfterRedeem = engine.getCollateralBalanceOfUser(user, weth);
        assertEq(userBalanceAfterRedeem, 0);
        vm.stopPrank();
    }

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(engine), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.redeemColleteralForDsc(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositColleteralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.startPrank(user);
        vm.expectEmit(true, true, true, true, address(engine));
        emit collateralRedeemed(user, user, weth, amountCollateral);

        engine.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    ///////////////////////////////////
    // burnDsc Tests //
    ///////////////////////////////////

    function testCantBurnMoreThanUserHas() public {
        vm.prank(user);
        vm.expectRevert();
        engine.burnDSC(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(engine), amountToMint);
        engine.burnDSC(amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = engine.getHealthFactor(user);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // function testCantLiquidateGoodHealthFactor()
    //     public
    //     depositedCollateralAndMintedDsc
    // {
    //     ERC20Mock(weth).mint(liquidator, collateralToCover);

    //     vm.startPrank(liquidator);
    //     ERC20Mock(weth).approve(address(engine), collateralToCover);
    //     engine.depositColleteralAndMintDSC(
    //         weth,
    //         collateralToCover,
    //         amountToMint
    //     );
    //     dsc.approve(address(engine), amountToMint);

    //     vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
    //     engine.liquidate(weth, user, amountToMint);
    //     vm.stopPrank();
    // }
}

//     ///////////////////////////////////
//     // mintDsc Tests //
//     ///////////////////////////////////
//     // This test needs it's own custom setup
//     function testRevertsIfMintFails() public {
//         // Arrange - Setup
//         MockFailedMintDSC mockDsc = new MockFailedMintDSC();
//         tokenAddresses = [weth];
//         feedAddresses = [ethUsdPriceFeed];
//         address owner = msg.sender;
//         vm.prank(owner);
//         DSCEngine mockDsce = new DSCEngine(
//             tokenAddresses,
//             feedAddresses,
//             address(mockDsc)
//         );
//         mockDsc.transferOwnership(address(mockDsce));
//         // Arrange - User
//         vm.startPrank(user);
//         ERC20Mock(weth).approve(address(mockDsce), amountCollateral);

//         vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
//         mockDsce.depositCollateralAndMintDsc(
//             weth,
//             amountCollateral,
//             amountToMint
//         );
//         vm.stopPrank();
//     }

//     function testRevertsIfMintAmountBreaksHealthFactor()
//         public
//         depositedCollateral
//     {
//         // 0xe580cc6100000000000000000000000000000000000000000000000006f05b59d3b20000
//         // 0xe580cc6100000000000000000000000000000000000000000000003635c9adc5dea00000
//         (, int256 price, , , ) = MockV3Aggregator(ethUsdPriceFeed)
//             .latestRoundData();
//         amountToMint =
//             (amountCollateral *
//                 (uint256(price) * dsce.getAdditionalFeedPrecision())) /
//             dsce.getPrecision();

//         vm.startPrank(user);
//         uint256 expectedHealthFactor = dsce.calculateHealthFactor(
//             amountToMint,
//             dsce.getUsdValue(weth, amountCollateral)
//         );
//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 DSCEngine.DSCEngine__BreaksHealthFactor.selector,
//                 expectedHealthFactor
//             )
//         );
//         dsce.mintDsc(amountToMint);
//         vm.stopPrank();
//     }

//     ///////////////////////////////////
//     // redeemCollateral Tests //
//     //////////////////////////////////

//     // this test needs it's own setup
//     function testRevertsIfTransferFails() public {
//         // Arrange - Setup
//         address owner = msg.sender;
//         vm.prank(owner);
//         MockFailedTransfer mockDsc = new MockFailedTransfer();
//         tokenAddresses = [address(mockDsc)];
//         feedAddresses = [ethUsdPriceFeed];
//         vm.prank(owner);
//         DSCEngine mockDsce = new DSCEngine(
//             tokenAddresses,
//             feedAddresses,
//             address(mockDsc)
//         );
//         mockDsc.mint(user, amountCollateral);

//         vm.prank(owner);
//         mockDsc.transferOwnership(address(mockDsce));
//         // Arrange - User
//         vm.startPrank(user);
//         ERC20Mock(address(mockDsc)).approve(
//             address(mockDsce),
//             amountCollateral
//         );
//         // Act / Assert
//         mockDsce.depositCollateral(address(mockDsc), amountCollateral);
//         vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
//         mockDsce.redeemCollateral(address(mockDsc), amountCollateral);
//         vm.stopPrank();
//     }

//     function testCanRedeemDepositedCollateral() public {
//         vm.startPrank(user);
//         ERC20Mock(weth).approve(address(dsce), amountCollateral);
//         dsc.approve(address(dsce), amountToMint);
//         dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
//         dsc.approve(address(dsce), amountToMint);
//         dsce.redeemCollateralForDsc(weth, amountCollateral, amountToMint);
//         vm.stopPrank();

//         uint256 userBalance = dsc.balanceOf(user);
//         assertEq(userBalance, 0);
//     }

//     function testHealthFactorCanGoBelowOne()
//         public
//         depositedCollateralAndMintedDsc
//     {
//         int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
//         // Remember, we need $200 at all times if we have $100 of debt

//         MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

//         uint256 userHealthFactor = dsce.getHealthFactor(user);
//         // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
//         // 0.9
//         assert(userHealthFactor == 0.9 ether);
//     }

//     // This test needs it's own setup
//     function testMustImproveHealthFactorOnLiquidation() public {
//         // Arrange - Setup
//         MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
//         tokenAddresses = [weth];
//         feedAddresses = [ethUsdPriceFeed];
//         address owner = msg.sender;
//         vm.prank(owner);
//         DSCEngine mockDsce = new DSCEngine(
//             tokenAddresses,
//             feedAddresses,
//             address(mockDsc)
//         );
//         mockDsc.transferOwnership(address(mockDsce));
//         // Arrange - User
//         vm.startPrank(user);
//         ERC20Mock(weth).approve(address(mockDsce), amountCollateral);
//         mockDsce.depositCollateralAndMintDsc(
//             weth,
//             amountCollateral,
//             amountToMint
//         );
//         vm.stopPrank();

//         // Arrange - Liquidator
//         collateralToCover = 1 ether;
//         ERC20Mock(weth).mint(liquidator, collateralToCover);

//         vm.startPrank(liquidator);
//         ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
//         uint256 debtToCover = 10 ether;
//         mockDsce.depositCollateralAndMintDsc(
//             weth,
//             collateralToCover,
//             amountToMint
//         );
//         mockDsc.approve(address(mockDsce), debtToCover);
//         // Act
//         int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
//         MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
//         // Act/Assert
//         vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
//         mockDsce.liquidate(weth, user, debtToCover);
//         vm.stopPrank();
//     }

//     modifier liquidated() {
//         vm.startPrank(user);
//         ERC20Mock(weth).approve(address(dsce), amountCollateral);
//         dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
//         vm.stopPrank();
//         int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

//         MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
//         uint256 userHealthFactor = dsce.getHealthFactor(user);

//         ERC20Mock(weth).mint(liquidator, collateralToCover);

//         vm.startPrank(liquidator);
//         ERC20Mock(weth).approve(address(dsce), collateralToCover);
//         dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
//         dsc.approve(address(dsce), amountToMint);
//         dsce.liquidate(weth, user, amountToMint); // We are covering their whole debt
//         vm.stopPrank();
//         _;
//     }

//     function testLiquidationPayoutIsCorrect() public liquidated {
//         uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
//         uint256 expectedWeth = dsce.getTokenAmountFromUsd(weth, amountToMint) +
//             ((dsce.getTokenAmountFromUsd(weth, amountToMint) *
//                 dsce.getLiquidationBonus()) / dsce.getLiquidationPrecision());
//         uint256 hardCodedExpected = 6_111_111_111_111_111_110;
//         assertEq(liquidatorWethBalance, hardCodedExpected);
//         assertEq(liquidatorWethBalance, expectedWeth);
//     }

//     function testUserStillHasSomeEthAfterLiquidation() public liquidated {
//         // Get how much WETH the user lost
//         uint256 amountLiquidated = dsce.getTokenAmountFromUsd(
//             weth,
//             amountToMint
//         ) +
//             ((dsce.getTokenAmountFromUsd(weth, amountToMint) *
//                 dsce.getLiquidationBonus()) / dsce.getLiquidationPrecision());

//         uint256 usdAmountLiquidated = dsce.getUsdValue(weth, amountLiquidated);
//         uint256 expectedUserCollateralValueInUsd = dsce.getUsdValue(
//             weth,
//             amountCollateral
//         ) - (usdAmountLiquidated);

//         (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(user);
//         uint256 hardCodedExpectedValue = 70_000_000_000_000_000_020;
//         assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
//         assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
//     }

//     function testLiquidatorTakesOnUsersDebt() public liquidated {
//         (uint256 liquidatorDscMinted, ) = dsce.getAccountInformation(
//             liquidator
//         );
//         assertEq(liquidatorDscMinted, amountToMint);
//     }

//     function testUserHasNoMoreDebt() public liquidated {
//         (uint256 userDscMinted, ) = dsce.getAccountInformation(user);
//         assertEq(userDscMinted, 0);
//     }

//     ///////////////////////////////////
//     // View & Pure Function Tests //
//     //////////////////////////////////
//     function testGetCollateralTokenPriceFeed() public {
//         address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
//         assertEq(priceFeed, ethUsdPriceFeed);
//     }

//     function testGetCollateralTokens() public {
//         address[] memory collateralTokens = dsce.getCollateralTokens();
//         assertEq(collateralTokens[0], weth);
//     }

//     function testGetMinHealthFactor() public {
//         uint256 minHealthFactor = dsce.getMinHealthFactor();
//         assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
//     }

//     function testGetLiquidationThreshold() public {
//         uint256 liquidationThreshold = dsce.getLiquidationThreshold();
//         assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
//     }

//     function testGetAccountCollateralValueFromInformation()
//         public
//         depositedCollateral
//     {
//         (, uint256 collateralValue) = dsce.getAccountInformation(user);
//         uint256 expectedCollateralValue = dsce.getUsdValue(
//             weth,
//             amountCollateral
//         );
//         assertEq(collateralValue, expectedCollateralValue);
//     }

//     function testGetCollateralBalanceOfUser() public {
//         vm.startPrank(user);
//         ERC20Mock(weth).approve(address(dsce), amountCollateral);
//         dsce.depositCollateral(weth, amountCollateral);
//         vm.stopPrank();
//         uint256 collateralBalance = dsce.getCollateralBalanceOfUser(user, weth);
//         assertEq(collateralBalance, amountCollateral);
//     }

//     function testGetAccountCollateralValue() public {
//         vm.startPrank(user);
//         ERC20Mock(weth).approve(address(dsce), amountCollateral);
//         dsce.depositCollateral(weth, amountCollateral);
//         vm.stopPrank();
//         uint256 collateralValue = dsce.getAccountCollateralValue(user);
//         uint256 expectedCollateralValue = dsce.getUsdValue(
//             weth,
//             amountCollateral
//         );
//         assertEq(collateralValue, expectedCollateralValue);
//     }

//     function testGetDsc() public {
//         address dscAddress = dsce.getDsc();
//         assertEq(dscAddress, address(dsc));
//     }

//     function testLiquidationPrecision() public {
//         uint256 expectedLiquidationPrecision = 100;
//         uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
//         assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
//     }

//     // How do we adjust our invariant tests for this?
//     // function testInvariantBreaks() public depositedCollateralAndMintedDsc {
//     //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(0);

//     //     uint256 totalSupply = dsc.totalSupply();
//     //     uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(dsce));
//     //     uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

//     //     uint256 wethValue = dsce.getUsdValue(weth, wethDeposted);
//     //     uint256 wbtcValue = dsce.getUsdValue(wbtc, wbtcDeposited);

//     //     console.log("wethValue: %s", wethValue);
//     //     console.log("wbtcValue: %s", wbtcValue);
//     //     console.log("totalSupply: %s", totalSupply);

//     //     assert(wethValue + wbtcValue >= totalSupply);
//     // }
// }
