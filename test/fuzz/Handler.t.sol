//SPDX License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "lib/openzepplin-contracts/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    //we want to get weth and wbtc so

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timeMintIsCalled;
    uint256 MAX_DEPOSIT_AMOUNT = type(uint96).max; // this give us the max num of uint96 .. theres a reson we didnt use uint256 .
    //cuz if we use it ,when calling the depositCollateral it will revert
    // uint256 maxAmountCollateralToRedeem =

    address[] public userCollateralDeposited;

    //we also want to update the price feed of contract
    // MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        // we store the two adrress here
        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        // ethUsdPriceFeed = MockV3Aggregator(getCollateralTokenPriceFeed(address(weth))); // now we have a ethusd priceFeed
    }

    // we wanmt to make sure that we cant redeem without making a deposit
    //we want to keep the randomization , we want to deposit reandom collaterals that are valid collaterals

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        //we got a valid collateral , so let get a valid amount collateral...    // we can use bound to get and combine min and max amount
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_AMOUNT);

        // after this we need to approve this protocol to deposit collateral..
        // we then allowe the msg.sender to mint little of the collateral so it can deposit it
        // we are setting this up so who so ever makes this actually has the collateral and actually will approve to  deposit the collateral
        // so this is why we are ussing the ERC20Mock so we can mint some of the collateral

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral); // this way the user wil be able to have the collateral
        collateral.approve(address(engine), amountCollateral);

        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // this will double push .. if the same address push twice
        //my personal note normally i would have done something like , if (!hasDeposited){hasDeposited == true} then push the user that has deposited ..
        userCollateralDeposited.push(msg.sender);
    }

    function redeemcollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        //let say there is a bug, where the user can redeem more than they have ... if i comment this maxAmountCollateralToRedeem out ..
        //fuzz test won't catch this because we have our fail_on_revert to be true .. it best to be cautois when using true
        uint256 maxAmountCollateralToRedeem = engine.getCollateralBalanceOfUser(address(collateral), msg.sender);
        //they should only be redeeming as much collateral they put in the system
        amountCollateral = bound(amountCollateral, 0, maxAmountCollateralToRedeem);
        //if the maxAmountCollateralToRedeem is zero , we will need to keep the min to be zero as well or esle it will break
        if (amountCollateral == 0) {
            return; //or we could a key word vm.assume ..but we wont be using that now
        }

        // herer the logic ,if the amountCollateral is zero just return and don't call the snippet below , which is redeemCollateral..if not it is going to fail
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        // in other to mint dsc we need to use an address than has collateral on it and not just any random address .. so we can get the address from the userCollateralDeposited array
        if (userCollateralDeposited.length == 0) {
            return;
        } // i will try to understand this one sooner
        //ARRAYS of addressSeed mode the usercollateralDeposited length
        address sender = userCollateralDeposited[addressSeed % userCollateralDeposited.length];
        (uint256 totalDSCMinted, uint256 totalColleteralValueInUsd) = engine.getAccountInformation(sender);

        int256 maxAmountToMint = (int256(totalColleteralValueInUsd) / 2) - int256(totalDSCMinted);

        // we want the amount value should be more than the system.. because we have revert if heart factor is broken
        // we should be only be able to mint dsc if the amount is less than the collateral
        if (maxAmountToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxAmountToMint));

        if (amount == 0) {
            return;
        }

        console.log("collateral:", totalColleteralValueInUsd);
        console.log("minted:", totalDSCMinted);
        console.log("amount after bound:", amount);
        console.log("maxAmountToMint:", maxAmountToMint);

        vm.startPrank(sender);
        engine.mintDSCToken(amount);
        vm.stopPrank();
        timeMintIsCalled++;
        // it has'nt find a way to mint more token than collateral in the system
    }

    //this breaks the contracts ..so we aint putting it and can be considered a bug
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceint = int256(uint256(newPrice));    //converting it to int
    //     ethUsdPriceFeed.updateAnswer(newPrice);
    // }
    //Helper Function

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        //if collateral seed module 2 is == 0 .. then we can return weth or btc

        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}

// Continue on revert
// Fail on revert
