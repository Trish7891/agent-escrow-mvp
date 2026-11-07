# Ruling — <job_ref>

**Terms hash:** `0x…`
**Evidence bundle hash:** `0x…`
**Arbiter:** <address / ENS>
**Ruled at:** <UTC>
**Time from dispute to ruling:** <hh:mm>

## Outcome

`settled` / `failed` / `undecided`

One sentence a stranger can act on: *"<what happened, and where the money went>."*

## Claims table

Copy every acceptance test from the terms, in the original order, with the
result you found — not the result the seller claimed. The last column names
the rule the decision rests on.

| # | test id | claim | finding | decisive | rule |
|---|---|---|---|---|---|
| 1 | T1 | pass | pass | yes | R2 |
| 2 | T2 | pass | pass | yes | R2 |
| 3 | T3 | pass | **fail** | yes | R2, R4 |
| 4 | T4 | pass | pass | no | R3 |

`finding` is what you verified. `claim` is what was asserted. When they differ,
say why in one line each:

- T3: bundle `sha256` `a1b2…` does not match the delivered artifact `c3d4…`.

## Evidence reviewed

| artifact | sha256 | bytes | matches bundle |
|---|---|---|---|
| gauge.csv | `…` | 4,912 | yes |
| source_receipts.json | `…` | 1,204 | yes |

## Settlement check (R6)

| field | expected | observed | ok |
|---|---|---|---|
| chain | Base | Base | yes |
| payer | `0x…` (buyer) | `0x…` | yes |
| payee | `0x…` (seller) | `0x…` | yes |
| amount | 2000000 (USDC, 6d) | 2000000 | yes |
| nonce | prefixed `river-gauge-2026-11-a` | `river-gauge-2026-11-a-01` | yes |
| confirmations | ≥ 12 | 214 | yes |

## Why this outcome

Three sentences maximum. Name the decisive test and the rule. No adjectives
about anyone's character, no speculation about intent, no advice for next time.

## What was not decided

Anything a party raised that the terms do not cover, stated plainly and left
undecided. This is the section that keeps adjudication cheap — it is also the
list of things to write into the next job spec.

- *Buyer raised that the file was "hard to read". No acceptance test covers
  formatting, so it did not affect the outcome.*

## Funds movement

| leg | amount | tx |
|---|---|---|
| principal → buyer/seller | | `0x…` |
| fee → arbiter | | `0x…` |
| dispute stake returned/forfeited (R10) | | `0x…` |

## Signatures

Two of three owners signed. Attach the Safe transaction hash:

`0x…`
