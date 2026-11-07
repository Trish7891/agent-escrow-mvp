# One-week validation runbook: one real $100 job

The goal is not to launch a product. It is to answer one question with real
money and a real counterparty:

> Will a person put $100 into escrow for agent work, and will the paperwork
> survive contact with an actual job?

Seven days, $100 of float, one job, one published ruling. If it works you have
a case study and a revenue line. If it fails you have a cheap, specific reason.

**Do not use `src/AgentEscrow.sol` for this.** It is unaudited. This runbook
uses a 2-of-3 multisig, which has the same trust shape for a single job and
zero contract risk.

---

## Success criteria (all four)

| # | criterion | measure |
|---|---|---|
| C1 | a human, not an agent, funds $100 | on-chain transfer to the escrow address from a wallet the buyer controls |
| C2 | terms were fixed before funding | `terms_hash` published at a timestamp earlier than the funding tx |
| C3 | the work is judged on evidence, not vibes | validator passes on a complete bundle; ruling cites rules R1–R14 |
| C4 | the ruling is public and paid for | published ruling + `$10` fee received |

**Kill criteria — stop the week and write it up:**

- no buyer has agreed by end of Day 4
- the buyer refuses a written acceptance spec ("just trust me" — that is the
  whole problem statement, and answering it is the product)
- adjudication takes more than 2 hours of your time for $10
- you find yourself making an exception "just this once" to any rule in
  `docs/adjudication.md`

Any one of those means the thesis is wrong in its current form. That is a
result, not a failure.

---

## Day 0 — setup (90 minutes)

**1. Create the multisig.** https://app.safe.global → *Create new Safe* →
network **Base** → owners: buyer, seller, you (arbiter) → threshold **2 of 3**
→ deploy.

> Why 2-of-3: no single key can move funds, you cannot release alone, and the
> buyer cannot claw back alone. That is exactly what a custodial escrow would
> give them, without you holding anything. Cost on Base is cents; confirm the
> exact figure on Basescan before you quote it to anyone.

Record:

```
SAFE=<0x...>          # escrow address for this job
BUYER=<0x...>
SELLER=<0x...>
ARBITER=<0x...>
```

**2. Write the job spec** from `examples/job-river-gauge.json`. For a $100
ticket, replace the $2 amount and tighten the tests. Rules for writing it:

- 3–6 acceptance tests, at least 2 `deterministic`
- every test must be checkable by someone who was not in the conversation
- `deadline_utc` generous (72h for a first job), `review_window_seconds` 48h
- `silence_outcome: "refund"` for the first job — a buyer going quiet must not
  hand you a win you have to defend
- name the arbiter (you) and state the fee

```bash
python3 tools/validate.py my-job.json --check-terms
# copy terms_hash into the file, re-run until it is 0 failures
```

**3. Publish the terms before any money moves.** A GitHub Gist or a commit in
this repo. The timestamp is the point: it proves terms existed before funding,
which is the only thing that makes "you changed the spec afterwards" impossible.

**4. Send the buyer three things, in one message:** the published spec link,
the Safe address, and the exact sentence *"the $10 fee is taken from the
released amount, so if the work fails you get all $100 back."*

No spec, no funding. That ordering is the product.

---

## Day 1–2 — find the buyer

The buyer must be a person with a real, boring, checkable task. Good shapes:

- data collection with a source of truth (prices, filings, regulations, feeds)
- a document they must produce anyway (summaries, comparisons, extracts)
- monitoring with a defined trigger and a defined alert format

Bad shapes: anything whose success is "does it feel good", anything where the
buyer cannot state acceptance criteria in writing, anything requiring access
you do not have.

Where to look, in order of conversion odds:

1. **People already paying for something adjacent** — a VA, a freelancer, a
   scraper subscription. They have a budget line and a pain.
2. **Communities where agents are discussed and money is real** — small
   business ops, research groups, trading-adjacent.
3. **Your own network first.** One yes beats fifty impressions.

Pitch, short version:

> I run a small escrow for agent work. You write what "done" means, I hold
> $100 in a 2-of-3 multisig you control a key to, an agent does the job, and I
> rule on the evidence if you disagree. Fee is $10, and only if it succeeds.

Send the spec, not a deck.

---

## Day 2–3 — funding

1. Buyer sends **$100 USDC on Base** to `$SAFE`.
2. Verify yourself before telling anyone it is funded:

```bash
cast balance --erc20 $USDC $SAFE --rpc-url https://mainnet.base.org
cast tx $FUNDING_TX --rpc-url https://mainnet.base.org | head -20
```

3. Record the funding tx hash in the job record. C2 is now satisfied.

If the buyer stalls at this step, that is the finding — not a reason to offer
credit terms.

---

## Day 3–5 — delivery

The seller (agent, or you operating one) produces the evidence bundle:

```bash
sha256sum gauge.csv source_receipts.json
# fill artifacts[].sha256, claims[].result, settlement block
python3 tools/validate.py my-job.json my-evidence.json --check-terms
```

Send the buyer the bundle hash and a one-paragraph summary. Say explicitly:

> Acceptance window closes <UTC timestamp>. If I hear nothing by then the job
> resolves as `refund` and no fee is charged.

That sentence is R8 in action, and it is what makes the deadline real.

---

## Day 5–6 — ruling (or non-ruling)

**If the buyer accepts:** release via Safe (buyer + you sign), pay yourself the
$10 from the released amount, record `settled`.

**If the buyer disputes:** they post a reason; you apply `docs/adjudication.md`
literally, test by test, and publish the ruling. Both signatures then execute
the outcome.

**If the buyer goes silent:** do nothing until the window expires, then refund
and record `undecided`. Do not "helpfully" release. Do not chase twice.

The ruling document is fixed-format — use `templates/ruling.md`. It must name
the rule behind every decision. If you cannot name the rule, the ruling is not
finished.

---

## Day 7 — publish and count

Publish, in one place:

- job spec + `terms_hash` + timestamp
- evidence bundle (or its hashes, if the buyer wants privacy)
- ruling, with the claims table
- Safe address, funding tx, release/refund tx
- timings and costs

Then fill this in honestly:

| metric | value |
|---|---|
| time from pitch to funded | |
| time from funded to delivered | |
| your minutes spent adjudicating | |
| gas paid (all txs) | |
| fee collected | |
| outcome | settled / failed / undecided |
| would the buyer do it again? (ask directly) | |

---

## Cost model for the week

| item | cost |
|---|---|
| Safe deployment + funding tx | cents on Base |
| release or refund tx | cents on Base |
| your time | 3–5 hours total |
| capital at risk | $0 (you never hold principal) |
| downside if buyer vanishes | one refund tx, `undecided` recorded |

Revenue in the success case: **$10**. That is not the point of week one. The
point is C1–C4 and the number in the "would they do it again" row.

---

## What week two looks like, conditionally

- **C1–C4 all met, buyer says yes again** → raise the ticket to $500, keep 10%,
  and only now consider deploying the contract (after an audit quote).
- **Met, but buyer says no** → the fee is too high relative to trust gained, or
  the spec-writing burden is on the wrong side. Test pricing at $5 flat.
- **No buyer by Day 4** → the demand is not there at $100 for stranger-to-
  stranger agent work. Pivot to adjudication-as-a-service for people already
  using someone else's escrow rail: same rules, no float, no Safe, charge per
  case.
- **Adjudication ate the week** → the product is the spec writer, not the
  escrow. Sell the spec and the ruling template.

---

## Honest accounting of what this proves

One job proves the mechanics and the paperwork survive a real counterparty. It
does not prove a market. Two paid jobs from two unrelated buyers is the
smallest thing that could be called evidence of demand, and even that is a
sample of two.

Write the number down anyway. A published `$10` with a real ruling attached is
worth more than any amount of TAM arithmetic.
