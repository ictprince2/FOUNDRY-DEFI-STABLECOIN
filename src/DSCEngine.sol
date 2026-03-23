//SPDX License-Identifier: MIT

pragma solidity ^0.8.19;

/*
 * @title DSCEngine
 * @author ICT PRINCE
 *
 * The system is designed to be as minimal as possible, and have the token maintian a 1 token = $1peg.
 * This StableCoin Has This Features:
 * - Exogeneus colleteral
 * - Dollar pegged
 * - Algoritmically Stable
 *
 * it is similar to DAI if DAI had no governace, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC should always be "Overcolleteralized". At no point should the value of all colleteral <= the value of all the DSC
 * @notice This contract is the core of DSC system. it handles all the logic for mining and redeeming DSC, as well as depositing and withdrawing colleteral.
 * @notice This contract is VERY lowly based on MakerDAO (DAI) system.
 *
 */

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

import {ReentrancyGuard} from "lib/openzepplin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "lib/openzepplin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {OracleLib} from "../libraries/OracleLib.sol";

contract DSCEngine is ReentrancyGuard {
    using OracleLib for AggregatorV3Interface;
    ///////////////////////////////
    //  ERRORS                   //
    ///////////////////////////////

    error DSCEngine__NotZeroAddress();
    error DSCEngine__NeedMoreColleteral();
    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__tokenAddressesAndpriceFeedsAddresssesMustHaveTheSameLenght();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFalied();

    ///////////////////////////////
    //  STATE VARIABLES           //
    ///////////////////////////////
    //Storage structures

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //it means i need to be 200%  or 150% over colleterized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_THRESHOLD = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus for liquidators

    mapping(address token => address priceFeed) private s_priceFeed;

    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    mapping(address user => uint256 amountDSCToMint) private s_amountDSCMinted;
    address[] private s_collateralTokens; // wETH -> ETH/USD and more stored here

    // address wETH;
    // address wBTC;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////////////////
    //  EVENTS                   //
    ///////////////////////////////

    event collateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    event collateralRedeemed(address indexed redeemFrom, address indexed to, address indexed token, uint256 amount);
    ///////////////////////////////
    //  MODIFIERS                //
    ///////////////////////////////
    //Function Guards

    modifier amountNotZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeed[tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////////////////////
    //  FUNCTIONS                //
    ///////////////////////////////
    //we are going to be using the USD PriceFeeds..
    constructor(address[] memory tokenAddresses, address[] memory priceFeedsAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedsAddresses.length) {
            revert DSCEngine__tokenAddressesAndpriceFeedsAddresssesMustHaveTheSameLenght();
        }
        //in order for use to get the pricing we have to use USD priceFeed
        //for Example, BTC / USD, ETH / USD, MKR / USD
        //we are going to loop through

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedsAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////////////
    // EXTERNAL FUNCTIONS        //
    ///////////////////////////////
    function depositColleteralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountOfColleteral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountOfColleteral);

        mintDSCToken(amountDSCToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountOfColleteral)
        public
        amountNotZero(amountOfColleteral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        //first thing we need to do is a way to track how muchh colleteral will be somebody has deposited,which we will be uing mapping

        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountOfColleteral;
        //we just updated the state next we have to emit an event
        emit collateralDeposited(msg.sender, tokenCollateralAddress, amountOfColleteral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountOfColleteral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress the address of the token they want to redeem
     * @param amountOfCollateral the amount of collateral they want to redeem
     * @param amountDscToBurn the amount of DSC they want to burn
     * This function Burns and Redeems underlying collateral at the same time, in order to make sure the health factor is always above 1, and they can never be undercolleteralized.
     * @notice they have to burn the DSC first before we redeem the collateral, because if we redeem the collateral first, they might be undercolleteralized and get liquidated.
     * @notice they can only redeem the amount of collateral that is worth the amount of DSC they are burning. if they want to redeem more than that, they have to burn more DSC.
     * @notice follow CEI check, effect , interaction
     * @notice health factor must be over 1 after collateral pulled out, if not we will revert the transaction, because they will be undercolleteralized and can get liquidated.
     */

    function redeemColleteralForDsc(
        address tokenCollateralAddress,
        uint256 amountOfCollateral,
        uint256 amountDscToBurn
    ) external {
        //first we will  burn before we redeem
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountOfCollateral);

        // the health factor check is already in the burn function and redeem collateral function, so we dont need to check it here again.
    }

    /**
     * in order to redeem colleteral , they have to send back the DSC they minted, and then we will give them back the colleteral they deposited.
     * @notice they can only redeem the amount of colleteral that is worth the amount of DSC they are burning. if they want to redeem more than that, they have to burn more DSC.
     * 1. health factor must be over 1 after coolateral pulled out, if not we will revert the transaction, because they will be undercolleteralized and can get liquidated.
     * DRY: Dont repeat yourself, we already have a function that checks the health factor, so we will just call that function.
     * CEI check, effect, interaction
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountOfCollateral)
        public
        amountNotZero(amountOfCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountOfCollateral);
        _revertHealthFactorIsBroken(msg.sender);

        // 200 eth -> 50 DSC
        // 200 eth(break healthfactor)
        //first 1. we need to burn the dsc
        // 2. reedem the collateral
    }

    /**
     * @notice follow CEI check, effect , interaction
     * @notice they must have more colleteral value than the minimum threshold.
     */
    //CEI
    //in other to mint DSC , we have to make sure the colleteral value > than the DSC amount   //we will be checking values , price feeds etc.

    // Mint Stablecoin //
    function mintDSCToken(uint256 amountDSCToMint) public amountNotZero(amountDSCToMint) nonReentrant {
        // to keep track of the address minted
        s_amountDSCMinted[msg.sender] += amountDSCToMint;
        //if they minted too much .. they minted ($150 DSC worth of dsc ,but they only have $100 worth of ETH )it will be way too much
        _revertHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFalied();
        }
    }

    function burnDSC(uint256 amountDscToBurn) public {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);

        _revertHealthFactorIsBroken(msg.sender); // i dont think this will ever hit
    }

    // if we start nearing undercollateralization, we want to start liquidating positions

    // $100 ETH backing 50 DSC -> 200% collateralization ratio
    // $20 ETH backing 50 DSC -> 40% collateralization ratio (under collateralized, we want to liquidate)
    // if we have a liquidation threshold of 150% , then we want to start liquidating if the collateralization ratio goes below 150% , which means the health factor goes below 1.5

    // $75 ETH backing 50 DSC -> 150% collateralization ratio (at risk of being liquidated, we want to start liquidating)
    // liquidator takes the $75 ETH and burns the 50 DSC, which brings the collateralization ratio back to 200% , and the health factor back to 1.5

    // if someone is almost undercollateralized , we will pay them to liquidate the position, which means they will burn the DSC and take the collateral, which brings the system back to a healthy state.

    /**
     * @param collateral the erc20 collateral address to liquidate from the user
     * @param user the user to liquidate, who has broken the health factor threeshold. their threeshold should be below MIN_HEALTH_THRESHOLD
     * @param debtToCover the amount of DSC the liquidator wants to burn to improve the user health factor.
     * @notice you can partially liquidate a user.
     * @notice you will get liquidation bonus for taking the user funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known Bug will be if the protocol is 100% or less collateralized, then  we wouldn't be able to incentive the liquidators.
     * for example if the price of the collateral plummated before anyone could be liquidated.
     *
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        amountNotZero(debtToCover)
        nonReentrant
    {
        // 1. check the health factor of the user, if it is above the threshold, we will revert
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor >= MIN_HEALTH_THRESHOLD) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
        // 2. we will burn the liquidator debt
        // and take their collateral
        // Bad : $140 ETH , $100 DSC
        //debtToCover = $100
        // $100 of DSC = ??? ETh?? thids will be $100 / $2000 = 0.05 ETH
        // 0.05 ETH = $100 DSC

        // 3. we will transfer the collateral to the liquidator with a bonus
        uint256 totalAmountFromDebtCovered = getCollateralAmountToLiquidate(collateral, debtToCover);
        // 10% bonus for liquidators
        // so we are giving them $110 worth of WETH for $100 DSC
        // we should implement a feature to liquidate in the event the protocol insolvent
        // Add sweep extra amount into a treasury

        // 0.05 ETH 0.1 = 0.005 ETH bonus
        uint256 bonusCollateral = (totalAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // we have to add collateral to the actual collateral
        uint256 totalcollateralToRedeem = totalAmountFromDebtCovered + bonusCollateral;
        // we need to burn dsc

        _burnDsc(user, msg.sender, debtToCover);

        _redeemCollateral(user, msg.sender, collateral, totalcollateralToRedeem);

        s_collateralDeposited[user][collateral] -= totalAmountFromDebtCovered;

        bool success = IERC20(collateral).transfer(msg.sender, totalAmountFromDebtCovered + bonusCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertHealthFactorIsBroken(msg.sender);
    }

    function getCollateralAmountToLiquidate(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // price of ETH for the token
        // $/ETH
        // $2000 / ETH =  $1000 / $2000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // (10e18 * 10e10 * 1 ETH) / 10e18 = 2000 USD
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    // ///////////////////////////////
    // PRIVATE AND INTERNAL VIEWS FUNCTIONS //
    /////////////////////////////////////////

    /**
     * Returns how close to liquidatedaion a user is
     * if a user goes below 1, then they cant get liquidated
     *
     */

    /*
     *@dev Low-level internal function, do not call unless the function calling it is
     * checking for health factor breaking down
     */
    function _burnDsc(address onBehalfOf, address from, uint256 amountDscToBurn) private {
        s_amountDSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(from, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 totalColleteralValueInUsd)
    {
        totalDSCMinted = s_amountDSCMinted[user];
        totalColleteralValueInUsd = _getAccountCollateralValue(user);
        return (totalDSCMinted, totalColleteralValueInUsd);
    }

    function _healthFactor(address user) private view returns (uint256) {
        //we are gonna need to get the total DSC minted and
        //total colleteral value .. so we will create a new function
        (uint256 totalDSCMinted, uint256 totalColleteralValueInUsd) = _getAccountInformation(user);

        return _calculateHealthFactor(totalDSCMinted, totalColleteralValueInUsd);

        // uint256 colleteralAdjustedForThreshold =
        //     (totalColleteralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // // $150 ETH / 100 DSC = 1.5

        // // $1000 * 50 = 50000/100 = 500/100   the 500 is the liquidation threshold

        // return (colleteralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    // 1. check the health factor (if the user has enough collateral to mint)
    // 2. if they dont the we revertt
    function _revertHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor < MIN_HEALTH_THRESHOLD) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountOfCollateral)
        private
        amountNotZero(amountOfCollateral)
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountOfCollateral;

        emit collateralRedeemed(from, to, tokenCollateralAddress, amountOfCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountOfCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _calculateHealthFactor(uint256 totalDSCMinted, uint256 totalColleteralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDSCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedToThreshold =
            (totalColleteralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedToThreshold * 1e18) / totalDSCMinted;
    }

    ///////// ///////////////////////////////
    // PUBLIC AND EXTERNAL VIEWS FUNCTIONS //
    /////////////////////////////////////////

    function _getAccountCollateralValue(address user) public view returns (uint256 totalColleteralValueInUsd) {
        // now to get the actual value , we will need to loop through each collateral token , get the amount they have deposited , and map iot to
        // the price , to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalColleteralValueInUsd += getUsdValue(token, amount);
        }
        return totalColleteralValueInUsd;
    }

    function calculateHealthFactor(uint256 totalDSCMinted, uint256 totalColleteralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDSCMinted, totalColleteralValueInUsd);
    }

    //Price Conversion//

    ///////// ///////////////////////////////
    // GETTER FUNCTIONS //
    /////////////////////////////////////////
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //we have to convert the price to 18 decimals , because we are using 18 decimals for our dsc token
        //Example: 1 ETH = $2000
        //Chainlink returns: 2000 * 10^8 = 200000000000
        //Convert: (200000000000 * 10^10 * 1 ETH) / 10^18 = 2000 USD
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 totalColleteralValueInUsd)
    {
        (totalDSCMinted, totalColleteralValueInUsd) = _getAccountInformation(user);
    }

    // function getUsdValue(
    //     address token,
    //     uint256 amount // in WEI
    // )
    //     external
    //     view
    //     returns (uint256)
    // {
    //     return getUsdValue(token, amount);
    // }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getPrecision() external returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external returns (uint256) {
        return MIN_HEALTH_THRESHOLD;
    }

    function getCollateralTokens() external returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeed[token];
    }

    function getHealthFactor(address user) external returns (uint256) {
        return _healthFactor(user);
    }
}
