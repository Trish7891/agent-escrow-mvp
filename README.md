# agent-escrow-mvp

Non-custodial escrow for agent work, with a commission charged **only when
work is verified and funds reach the seller**. Built as a two-day spike off the
Moltbook agent-economy data — the mechanism is real, the market is not where
most people think it is (see [Limits](#limits)).

What is here:

| piece | path | status |
|---|---|---|
| escrow contract | `src/AgentEscrow.sol` | compiles, 16/16 tests pass, exercised end-to-end on a local chain |
| job spec schema | `schema/job.schema.json` | validates the worked example |
| evidence bundle schema | `schema/evidence.schema.json` | validates the worked example |
| validator | `tools/validate.py` | checks spec + bundle + cross-bindings, recomputes `terms_hash` |
| terms guide | `docs/job-spec.md` | how to write a job that can actually be judged |
| decision procedure | `docs/adjudication.md` | 14 rules + failure taxonomy |
| validation runbook | `docs/validation-week.md` | one real $100 job, seven days, kill criteria |
| ruling template | `templates/ruling.md` | fixed-format public ruling |
| worked example | `examples/` | $2 USDC job, 4 tests, refund-on-silence |
| deploy script | `script/Deploy.s.sol` | Base Sepolia / Base |

## The design in one paragraph

The operator never holds funds or keys. A buyer funds a per-job escrow
against a `terms_hash` that was published before funding. The seller delivers
an evidence bundle whose hash goes on-chain. Funds release on buyer acceptance,
on pre-agreed silence, or on a signed arbiter ruling. Commission is taken from
the released amount and is zero on refunds and zero on unresolved jobs. Chain
state answers "was the money paid"; the evidence bundle plus the arbiter
answers "was the work done". Those are two different questions and merging
them is the usual reason escrow products rot.

## Quickstart

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge test                                   # 16 tests
python3 tools/validate.py \
  examples/job-river-gauge.json \
  examples/evidence-river-gauge.json --check-terms
```

Verified output at commit time:

```
Suite result: ok. 16 passed; 0 failed; 0 skipped
0 failures, 0 warnings
```

## Commission model

`feeBps` is set per job at creation, capped at 1000 (10%). Fee is taken from
the released amount, never from the buyer's principal on a refund.

| job | fee @5% | net after L2 gas | verdict |
|---|---|---|---|
| $1 | $0.05 | loses money | don't |
| $20 | $1.00 | marginal | maybe |
| $100 | $5.00 | fine | target floor |
| $500 | $25.00 | good | target |
| $2,000 | $100.00 | very good | enterprise-ish |

Commission on `$0.01` agent-to-agent x402 traffic is not a business. The
addressable buyers are humans (or orgs) hiring agents for real work at `$100+`
tickets.

## End-to-end run (local chain)

```bash
anvil --port 8545
forge create src/AgentEscrow.sol:AgentEscrow \
  --rpc-url http://127.0.0.1:8545 --private-key $PK --broadcast \
  --constructor-args $ARBITER $FEE_RECIPIENT 10000000000000000
# 1 ETH job, 5% fee
cast send $ESC "createJob(address,uint64,uint64,bool,bytes32,uint16)" \
  $SELLER $DEADLINE 3600 true $(cast keccak "spec-v1") 500 \
  --value 1ether --private-key $BUYER_PK --rpc-url $RPC
cast send $ESC "deliver(uint256,bytes32)" 1 $(cast keccak "evidence-v1") \
  --private-key $SELLER_PK --rpc-url $RPC
cast send $ESC "accept(uint256)" 1 --private-key $BUYER_PK --rpc-url $RPC
```

Measured on that run: seller `+0.949956 ETH` (0.95 less 44 µETH of gas for the
deliver transaction), treasury `+0.050000 ETH`, state `Funded(1) →
Delivered(2) → Released(3)`, `quoteFee` returns 0 after release.

## States

```
Funded ──deliver──▶ Delivered ──accept────────▶ Released  (fee taken)
  │                     │
  │                     ├──dispute (stake)─▶ Disputed ──rule(true)──▶ Released
  │                     │                              └─rule(false)─▶ Refunded
  │                     └──silence window──▶ release or refund per job terms
  └──deadline passes──▶ Refunded  (no fee)
Disputed ──arbiter timeout──▶ Unresolved  (principal back, stake back, no fee)
```

## Limits

Honest list, because most escrow pitches skip it:

- **Not audited.** Do not put real money through `src/AgentEscrow.sol`.
- **Push payments.** `_send` uses `call`; production wants pull-payment
  withdrawals so a reverting recipient cannot block a ruling.
- **Single arbiter per deployment.** Production wants a per-job arbiter with a
  bond and a rotation, so R9's timeout has teeth.
- **No partial release.** Deliberate (R7), and it will lose some deals.
- **Gas versus ticket size.** Below ~$20 the fee does not cover the two
  settlement transactions plus reconciliation.
- **Market risk, the real one.** The 30-day x402 sweep showed 37,495 sellers
  and a median seller earning $0.01. Only 91 cleared $100. Escrow for agents
  is a bet that humans start hiring agents for $100+ jobs, not a bet on the
  current micropayment volume.
- **Regulatory.** Non-custody is chosen partly because holding client crypto
  in South Africa pulls in CASP/FAIS obligations (segregated accounts, Travel
  Rule, minimum capital). The operator must never touch principal; if that
  ever changes, get a licence first.

## The one-week validation, if you want to test it for real

Full day-by-day version with commands, cost model and kill criteria:
[`docs/validation-week.md`](docs/validation-week.md). The short version:

1. One real `$100` job with a person (not an agent) as buyer.
2. 2-of-3 multisig on Base instead of the contract — faster to set up, same
   trust shape for one job.
3. You as arbiter, using `docs/adjudication.md` verbatim.
4. Publish the ruling with its evidence bundle, settled/failed/undecided
   included.
5. Charge 10% → `$10` revenue, and a documented adjudication you can point at.

If step 5 is the only money made, the answer is that adjudication is the
product and escrow is the wrapper. That is a fine answer, and cheaper to learn
in a week than in a year.
