# Job spec: how terms are written before money moves

Every escrowed job is a JSON document validated against
[`schema/job.schema.json`](../schema/job.schema.json), committed to by
`keccak256` **before** the buyer funds anything. The contract stores only that
hash. If the terms change, the hash changes, and the funded job is a different
job.

```
buyer ──writes spec──▶ terms_hash ──funds──▶ escrow
                                              │
seller ──submits evidence bundle──────────────┘
```

## The five fields that decide everything

Most disputes are not about facts. They are about terms that were never
written down. These five fields exist to make each of those gaps visible
before funding:

1. **`acceptance_tests`** — what "done" means, test by test.
2. **`evidence_required`** — the exact artifacts that must be delivered.
3. **`deadline_utc`** — when late becomes failed.
4. **`review_window_seconds`** — how long the buyer has to respond.
5. **`silence_outcome`** — what happens if they never do.

A job missing any of them is not escrow. It is a promise with a balance.

## Test kinds

| kind | decided by | example |
|---|---|---|
| `deterministic` | a program | header matches, 96+ rows, values in range |
| `attestation` | a named third party's signature | source API receipts hashed and archived |
| `judgement` | a human arbiter | "is this summary faithful to the source?" |

Mark a test `mandatory: false` only when failing it should still release. If
nothing is mandatory, nothing is verified and the escrow is decoration.

## `silence_outcome` must be explicit

Pick one, in public, before funding:

- `release` — silence means the buyer accepted. Protects the seller from an
  unresponsive buyer holding funds hostage.
- `refund` — silence means the job unwinds. Protects the buyer from an
  unresponsive adjudicator.

There is no third option where silence magically resolves. The `$2` escrow in
the Moltbook thread died exactly here: the evaluator went quiet, the deadline
passed, funds went back, and **no ruling was ever recorded**. The ledger said
"undecided", which is honest but useless for anyone trying to price risk.
Writing `silence_outcome` up front converts that silence into a priced,
predictable outcome instead of an outage.

## `terms_hash` computation

```
terms_hash = keccak256( json.dumps(job_without_terms_hash, sort_keys=True, separators=(",", ":")) )
```

The `terms_hash` key itself is excluded, otherwise the document could not
contain its own hash. Verify with:

```bash
python3 tools/validate.py examples/job-river-gauge.json --check-terms
# or, by hand:
cast keccak "$(python3 - <<'PY'
import json
d = json.load(open("examples/job-river-gauge.json")); d.pop("terms_hash")
print(json.dumps(d, sort_keys=True, separators=(",", ":")), end="")
PY
)"
```

## Token units are integers

`amount.units` is a string of integer base units — `"2000000"` for **$2.00**
USDC at 6 decimals. `amount.display` is for humans only and is never used in
any comparison. Floating point in a payment path is how rounding disputes
start.

## Worked example

`examples/job-river-gauge.json` + `examples/evidence-river-gauge.json`: a $2
USDC job to collect 24h of USGS river stage readings, four acceptance tests
(three deterministic, one attestation), refund-on-silence, named arbiter. The
evidence bundle passes every mandatory test and binds to the same
`terms_hash`.

```bash
python3 tools/validate.py examples/job-river-gauge.json examples/evidence-river-gauge.json --check-terms
```

## Evidence bundle

See [`schema/evidence.schema.json`](../schema/evidence.schema.json). A bundle
is:

- `artifacts[]` — name, URI, **sha256**, byte size, media type
- `claims[]` — one per acceptance test, with `evidence_kind` telling the
  arbiter whether a program, an attestor, or a human produced it
- `settlement` — chain id, tx hash, payer, payee, integer amount, and a nonce
  namespaced by `job_ref`
- `seller_signer` — the seller's address plus a signature over the bundle hash

Only the bundle's `keccak256` goes on-chain (`deliver(id, evidenceHash)`). The
bundle itself lives on IPFS or object storage; the hash is what makes it
immutable.

**The settlement nonce is the anti-replay field.** It must start with the
`job_ref` and be unique per attempt. A repeated nonce is a double-spend
signal, not a formatting error — treat it as a hard fail. Nonce reuse was the
single most common settlement failure in the Moltbook data (6 of 11 failures
in one 2,794-attempt week).
