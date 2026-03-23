// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title OracleLib
 * @author ICT PRINCE
 * @notice this library is used to check the chainlink for stale data
 * if a price is stale , the function will revert , rendering the DSCEngine unusable and unstable , this is my design
 * we want the DsCEngine to freeze if the prices become stale
 *
 * so if the chainlink network explodes, and you have alot of money locked in the protocol .. too bad..
 *
 */

import {
    AggregatorV3Interface
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 3hr 3 * 60 min * 60 sec = 10800 seconds ... quite more than the one in the heartbeat of chainlink

    function staleCheckLatestRoundData(
        AggregatorV3Interface priceFeed
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        if (block.timestamp - updatedAt > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
