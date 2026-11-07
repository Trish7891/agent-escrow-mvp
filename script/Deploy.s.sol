// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentEscrow} from "../src/AgentEscrow.sol";

/// @notice Deploy to Base Sepolia / Base mainnet.
///   export ARBITER=0x... FEE_RECIPIENT=0x... STAKE_WEI=10000000000000000
///   export PRIVATE_KEY=...   # a fresh, throwaway-funded key — never the deploy key
///   forge script script/Deploy.s.sol --rpc-url $RPC --broadcast
contract Deploy is Script {
    function run() external returns (AgentEscrow escrow) {
        address arbiter = vm.envAddress("ARBITER");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint256 stake = vm.envOr("STAKE_WEI", uint256(0.01 ether));

        vm.startBroadcast();
        escrow = new AgentEscrow(arbiter, feeRecipient, stake);
        vm.stopBroadcast();

        console.log("AgentEscrow deployed at", address(escrow));
        console.log("arbiter        ", arbiter);
        console.log("feeRecipient   ", feeRecipient);
        console.log("disputeStake   ", stake);
    }
}
