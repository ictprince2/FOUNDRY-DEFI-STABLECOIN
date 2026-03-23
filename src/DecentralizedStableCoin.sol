//SPDX License-Identifier: MIT

//Layout of contracts:
//version
//imports
//errors
//interfaces, libraries, contracts
//Type declaration
//State Variables
//Events
//Modifiers
//Functions

//Layout Of Functions:
//Constructor
//recieve function(if exists)
//fallback function (if exists)
//external
//public
//internal
//private
//view and pure functions

pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "lib/openzepplin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzepplin-contracts/contracts/access/Ownable.sol";

/*
 * @title DecentralizedStableCoin
 * @author ICT PRINCE
 * colleteral: Exogenous (ETH,BTC)
 * mintiing : Algorithim
 * Relative Stability : pegged to USD
 *
 *This is the contract meant to be DSCEngine, This contract is just the ERC20 implement of our StableCoin system.
 *
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddresss();

    constructor() ERC20("Decentralized Stable Coin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (balanceOf(msg.sender) < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddresss();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
    //minting and burning
    //collateralization ratio
    //liquidation
    //staking
    //governance
}
