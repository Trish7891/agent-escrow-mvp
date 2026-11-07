// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentEscrow} from "../src/AgentEscrow.sol";

contract AgentEscrowTest is Test {
    AgentEscrow esc;
    address buyer;
    address seller;
    address arbiter;
    address treasury;

    uint256 constant AMOUNT = 0.1 ether;       // a $100-ish job
    uint256 constant STAKE = 0.01 ether;
    uint16  constant FEE_BPS = 500;            // 5%
    bytes32 constant TERMS = keccak256("river-gauge-spec-v1");
    bytes32 constant EVIDENCE = keccak256("evidence-bundle-v1");

    event Released(uint256 indexed id, uint256 toSeller, uint256 fee);

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        arbiter = makeAddr("arbiter");
        treasury = makeAddr("treasury");
        vm.deal(buyer, 10 ether);
        esc = new AgentEscrow(arbiter, treasury, STAKE);
    }

    function _create(bool silenceReleases) internal returns (uint256 id) {
        vm.prank(buyer);
        id = esc.createJob{value: AMOUNT}(
            seller,
            uint64(block.timestamp + 2 days),
            1 hours,
            silenceReleases,
            TERMS,
            FEE_BPS
        );
    }

    function _deliver(uint256 id) internal {
        vm.prank(seller);
        esc.deliver(id, EVIDENCE);
    }

    // ---------------------------------------------------------------- happy

    function test_happyPath_sellerPaidFeeTaken() public {
        uint256 id = _create(true);
        _deliver(id);

        uint256 sellerBefore = seller.balance;
        vm.prank(buyer);
        esc.accept(id);

        uint256 fee = (AMOUNT * FEE_BPS) / 10_000;
        assertEq(seller.balance - sellerBefore, AMOUNT - fee);
        assertEq(treasury.balance, fee);
        assertEq(uint8(esc.getJob(id).state), uint8(AgentEscrow.State.Released));
    }

    function test_quoteFeeMatchesCharge() public {
        uint256 id = _create(true);
        assertEq(esc.quoteFee(id), (AMOUNT * FEE_BPS) / 10_000);
    }

    // ------------------------------------------------------------- failures

    function test_expiry_refundsBuyer_noFee() public {
        uint256 id = _create(false);
        vm.warp(block.timestamp + 3 days);

        esc.claimExpiry(id);

        assertEq(buyer.balance, 10 ether, "buyer made whole");
        assertEq(treasury.balance, 0, "no commission on failure");
        assertEq(uint8(esc.getJob(id).state), uint8(AgentEscrow.State.Refunded));
    }

    function test_silence_refundsWhenPreAgreed() public {
        uint256 id = _create(false);
        _deliver(id);
        vm.warp(block.timestamp + 1 hours + 1);

        esc.claimSilence(id);

        assertEq(buyer.balance, 10 ether);
        assertEq(treasury.balance, 0);
    }

    function test_silence_releasesWhenPreAgreed() public {
        uint256 id = _create(true);
        _deliver(id);
        vm.warp(block.timestamp + 1 hours + 1);

        esc.claimSilence(id);

        uint256 fee = (AMOUNT * FEE_BPS) / 10_000;
        assertEq(seller.balance, AMOUNT - fee);
        assertEq(treasury.balance, fee);
    }

    // ------------------------------------------------------------- disputes

    function test_dispute_buyerWins_stakeReturnsAndNoFee() public {
        uint256 id = _create(true);
        _deliver(id);

        vm.prank(buyer);
        esc.dispute{value: STAKE}(id);
        assertEq(uint8(esc.getJob(id).state), uint8(AgentEscrow.State.Disputed));

        vm.prank(arbiter);
        esc.rule(id, false);

        assertEq(buyer.balance, 10 ether - STAKE + STAKE, "amount + own stake back");
        assertEq(treasury.balance, 0);
        assertEq(seller.balance, 0);
    }

    function test_dispute_sellerWins_buyerStakeGoesToSeller() public {
        uint256 id = _create(true);
        _deliver(id);

        vm.prank(buyer);
        esc.dispute{value: STAKE}(id);

        vm.prank(arbiter);
        esc.rule(id, true);

        uint256 fee = (AMOUNT * FEE_BPS) / 10_000;
        assertEq(seller.balance, AMOUNT - fee + STAKE);
        assertEq(treasury.balance, fee);
    }

    function test_arbiterSilence_recordsUnresolved_notFailed() public {
        uint256 id = _create(true);
        _deliver(id);

        vm.prank(buyer);
        esc.dispute{value: STAKE}(id);

        vm.warp(block.timestamp + 30 days + 1);
        esc.claimArbiterSilence(id);

        assertEq(buyer.balance, 10 ether - STAKE + STAKE, "refunded");
        assertEq(treasury.balance, 0, "no fee");
        assertEq(uint8(esc.getJob(id).state), uint8(AgentEscrow.State.Unresolved));
    }

    // ------------------------------------------------------------ guards

    function test_deliverAfterDeadlineReverts() public {
        uint256 id = _create(true);
        vm.warp(block.timestamp + 2 days + 1);
        vm.prank(seller);
        vm.expectRevert(AgentEscrow.BadDeadline.selector);
        esc.deliver(id, EVIDENCE);
    }

    function test_onlySellerCanDeliver() public {
        uint256 id = _create(true);
        vm.prank(buyer);
        vm.expectRevert(AgentEscrow.NotSeller.selector);
        esc.deliver(id, EVIDENCE);
    }

    function test_onlyBuyerCanAccept() public {
        uint256 id = _create(true);
        _deliver(id);
        vm.prank(seller);
        vm.expectRevert(AgentEscrow.NotBuyer.selector);
        esc.accept(id);
    }

    function test_onlyArbiterCanRule() public {
        uint256 id = _create(true);
        _deliver(id);
        vm.prank(buyer);
        esc.dispute{value: STAKE}(id);
        vm.prank(buyer);
        vm.expectRevert(AgentEscrow.NotArbiter.selector);
        esc.rule(id, true);
    }

    function test_feeCeilingEnforced() public {
        vm.prank(buyer);
        vm.expectRevert(AgentEscrow.BadFee.selector);
        esc.createJob{value: AMOUNT}(
            seller, uint64(block.timestamp + 1 days), 1 hours, true, TERMS, uint16(1001)
        );
    }

    function test_cannotAcceptTwice() public {
        uint256 id = _create(true);
        _deliver(id);
        vm.prank(buyer);
        esc.accept(id);
        vm.prank(buyer);
        vm.expectRevert();
        esc.accept(id);
    }

    function test_zeroTermsRejected() public {
        vm.prank(buyer);
        vm.expectRevert(AgentEscrow.BadTerms.selector);
        esc.createJob{value: AMOUNT}(
            seller, uint64(block.timestamp + 1 days), 1 hours, true, bytes32(0), FEE_BPS
        );
    }

    function test_rightStakeRequired() public {
        uint256 id = _create(true);
        vm.prank(buyer);
        vm.expectRevert(AgentEscrow.WrongStake.selector);
        esc.dispute{value: STAKE - 1}(id);
    }
}
