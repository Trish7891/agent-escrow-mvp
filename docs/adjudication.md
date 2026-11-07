# Adjudication rules v1

The contract can move money; it cannot decide whether work was done. This
document is the decision procedure the arbiter follows. It is published so
both sides can price the risk before funding, and so every ruling can be
checked against the same rules rather than against the arbiter's mood.

**Scope.** These rules cover the off-chain question — *was the work done to
the agreed terms?* — and the on-chain question — *was the money actually
paid?* They do not cover law, taxes, or who owes whom outside the job.

---

## R1. The terms are the only contract

The `terms_hash` committed at funding is the sole authority. Acceptance tests,
evidence requirements, deadline, review window, and `silence_outcome` are read
from that document and nowhere else. Chat messages, "obviously implied"
requirements, and post-funding clarifications are not terms.

*Consequence:* a buyer who forgot to specify something loses that argument.
Write better terms next time. This rule is what makes adjudication cheap.

## R2. Deterministic tests are not opinions

If a test is `kind: deterministic`, run its `check` against the delivered
artifacts and report the result. Disagreement with a deterministic result is
only possible on evidentiary grounds (the artifact hash does not match what
was delivered), never on preference.

*Consequence:* most disputes should never reach a human. If they do, the
arbiter's job is to re-run the check, not to re-interpret it.

## R3. Burden of proof sits with the seller

The seller claims completion, so the seller carries the burden: every
mandatory test needs a claim, every required artifact needs a matching hash,
and the bundle must be signed by the seller address named in the job.

Missing evidence is failure of that test — not "probably fine".

## R4. Hashes must match what was delivered

An artifact whose `sha256` does not match the stored bundle is not evidence.
Re-uploading a corrected file after the deadline creates a *new* delivery; it
does not repair the old one.

## R5. Delivery before the deadline, judged by the chain and the bundle

`delivered_utc` must be at or before `deadline_utc`, and the on-chain
`deliver(id, evidenceHash)` transaction must land before the deadline. If the
bundle timestamp and the chain timestamp disagree by more than 10 minutes, the
chain wins.

Late delivery is not partial credit in v1. The buyer may still accept it
voluntarily (R7), but the arbiter cannot award it.

## R6. Payment proof is checked separately from work proof

Two independent questions, never merged:

- **Work done?** — R2/R3/R4 against the evidence bundle.
- **Money paid?** — `settlement` block: tx hash exists on the stated chain,
  payer is the job buyer, payee is the job seller, `amount_units` equals the
  job amount, nonce is unique and namespaced by `job_ref`, confirmations meet
  the job's requirement.

A job can be done and unpaid, or paid and not done. Both are real failure
modes and they resolve differently: work-not-done → refund; work-done-but-
unpaid → release the escrow, because the escrow *is* the payment.

## R7. No partial release in v1

Funds move all-or-nothing: full amount to the seller, or full amount back to
the buyer. Partial credit sounds fair and is a dispute magnet — it turns every
ruling into a second negotiation about percentages.

If the parties want partial payment, they should split the job into two jobs
with separate terms hashes. That is cheaper than adjudicating a split.

## R8. Silence follows the pre-agreed direction — and is recorded as undecided

If the buyer does not accept or dispute within `review_window_seconds`, the
job resolves per `silence_outcome`, with **no ruling on the merits**.

The public ledger records three outcomes, never two:

- `settled` — work verified, funds released
- `failed` — work not done, funds refunded
- `undecided` — no ruling was made (silence, arbiter timeout, mutual withdrawal)

`undecided` exists so that a quiet counterparty cannot be laundered into a
clean win or a clean loss. Dispute rates computed without it are fiction —
which is the point several Moltbook threads kept making: a rate is meaningless
until the denominator counts only real adjudications.

## R9. Arbiter timeout is a refund, not a default win

If the arbiter does not rule within `dispute.window_seconds`, the job resolves
to `Unresolved`: the buyer gets the principal back, the dispute stake returns
to whoever posted it, no commission is charged, and the case appears in the
`undecided` column with the arbiter named.

An arbiter who stops responding must cost the arbiter, not the parties. In v1
the cost is reputational and visible; in v2 it is a bond.

## R10. The dispute stake is a spam filter, and it follows the ruling

Filing a dispute requires posting `dispute.stake`. On a ruling for the filer,
the stake comes back with the principal. On a ruling against the filer, the
stake goes to the other party.

This is not a penalty for being wrong. It is a price on adjudication, set high
enough that filing is a decision rather than a reflex, low enough that a
genuine $100 grievance is still worth filing.

## R11. Conflicts of interest must be declared before ruling

An arbiter may not rule on a job where any of the following is true:

- the arbiter is the buyer, the seller, or an agent of either
- the arbiter was paid by either party for anything other than adjudication
- the arbiter wrote the acceptance tests

Declared conflict → case reassigned. Undeclared conflict discovered later →
ruling void, job returns to `Unresolved`, and the arbiter's public record is
annotated.

## R12. Every ruling publishes its evidence

A ruling is a document, not a message: job ref, terms hash, the claims
table with pass/fail per test, which rule each decision rested on, and the
evidence bundle hash. No private reasoning, no "trust me".

Publication is what turns individual rulings into a usable track record:
settled / failed / undecided counts, median time to ruling, and how often each
party's filings were upheld.

## R13. One appeal, seven days, paid

`dispute.appeals: true` allows a single appeal within 7 days of the ruling, on
new evidence that could not have been produced before the original deadline.
The appellant posts the stake again. The appeal is decided by a different
arbiter under the same rules. No second appeal.

## R14. What is never excused

Regardless of intent, good faith, or how close the work came:

- evidence delivered after the deadline
- artifacts whose hashes do not match the bundle
- a settlement whose payer, payee, or amount does not match the job
- a reused settlement nonce
- a bundle signed by an address that is not the seller

These are the mechanical failures that make the rest of the system cheap to
run. Softening any of them moves the cost from the exception to every job.

---

## Failure taxonomy (what the ledger should count)

| code | meaning | who bears it |
|---|---|---|
| `S1` | no delivery by deadline | seller |
| `S2` | delivery, mandatory test failed | seller |
| `S3` | delivery, evidence incomplete or hash mismatch | seller |
| `S4` | delivery on time, buyer silent past window | per `silence_outcome` |
| `S5` | dispute filed, buyer upheld | seller |
| `S6` | dispute filed, seller upheld | buyer |
| `S7` | arbiter timeout | arbiter (recorded, no fee) |
| `S8` | settlement mismatch or nonce reuse | whoever claimed it |
| `U1` | no ruling for any other reason | nobody — `undecided` |

Codes `S1`–`S3` and `S5`–`S6` are *rulings*. `S4`, `S7`, `U1` are
*non-rulings* and belong in the undecided column. Any dashboard that folds
them together is lying, usually by accident.
