#!/usr/bin/env python3
"""Validate an AgentEscrow job spec and (optionally) an evidence bundle.

    python tools/validate.py examples/job-river-gauge.json
    python tools/validate.py examples/job-river-gauge.json examples/evidence-river-gauge.json
    python tools/validate.py job.json evidence.json --check-terms

Exit code 0 = every check passed, 1 = at least one hard failure.
Warnings never change the exit code; they are things a human arbiter should look at.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import jsonschema
    from jsonschema import Draft202012Validator
except ImportError:  # pragma: no cover
    sys.exit("jsonschema not installed: pip install jsonschema")

ROOT = Path(__file__).resolve().parent.parent
JOB_SCHEMA = ROOT / "schema" / "job.schema.json"
EVIDENCE_SCHEMA = ROOT / "schema" / "evidence.schema.json"


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.warnings: list[str] = []

    def fail(self, msg: str) -> None:
        self.failures.append(msg)
        print(f"  FAIL  {msg}")

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)
        print(f"  warn  {msg}")

    def ok(self, msg: str) -> None:
        print(f"  ok    {msg}")


def load(path: Path) -> dict:
    with path.open() as fh:
        return json.load(fh)


def schema_errors(doc: dict, schema_path: Path) -> list[str]:
    schema = load(schema_path)
    validator = Draft202012Validator(schema, format_checker=jsonschema.FormatChecker())
    out = []
    for err in sorted(validator.iter_errors(doc), key=lambda e: list(e.path)):
        where = "/".join(str(p) for p in err.path) or "<root>"
        out.append(f"{where}: {err.message}")
    return out


def canonical_terms_hash(job: dict) -> str | None:
    """keccak256 of canonical JSON with terms_hash removed, via `cast keccak`."""
    if not shutil.which("cast"):
        return None
    body = {k: v for k, v in job.items() if k != "terms_hash"}
    canonical = json.dumps(body, sort_keys=True, separators=(",", ":"))
    res = subprocess.run(["cast", "keccak", canonical], capture_output=True, text=True)
    return res.stdout.strip() if res.returncode == 0 else None


def check_job(job: dict, rep: Report, verify_terms: bool) -> None:
    print("job spec")
    errs = schema_errors(job, JOB_SCHEMA)
    if errs:
        for e in errs:
            rep.fail(f"schema: {e}")
        return
    rep.ok("matches schema/job.schema.json")

    ids = [t["id"] for t in job["acceptance_tests"]]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        rep.fail(f"duplicate test ids: {sorted(dupes)}")
    else:
        rep.ok(f"{len(ids)} acceptance tests, ids unique")

    if job["silence_outcome"] not in {"release", "refund"}:
        rep.fail("silence_outcome must be release or refund")
    else:
        rep.ok(f"silence outcome fixed in advance: {job['silence_outcome']}")

    if "dispute" not in job:
        rep.fail("no arbiter named: a job without an arbiter cannot be adjudicated")
    else:
        rep.ok(f"arbiter named: {job['dispute']['arbiter']}")

    mandatory = [t for t in job["acceptance_tests"] if t.get("mandatory", True)]
    if not mandatory:
        rep.warn("no mandatory tests: nothing can fail, so nothing is verified")

    for t in job["acceptance_tests"]:
        if t["kind"] == "attestation" and not t.get("attestor"):
            rep.fail(f"test {t['id']} is an attestation with no named attestor")
        if t["kind"] == "deterministic" and not t.get("check"):
            rep.fail(f"test {t['id']} is deterministic but has no machine-readable check")

    names = [a["name"] for a in job["evidence_required"]]
    if len(set(names)) != len(names):
        rep.fail("duplicate evidence_required names")

    if verify_terms:
        computed = canonical_terms_hash(job)
        if computed is None:
            rep.warn("cast not found, skipped terms_hash recomputation")
        elif computed != job.get("terms_hash"):
            rep.fail(f"terms_hash mismatch: file says {job.get('terms_hash')}, canonical JSON hashes to {computed}")
        else:
            rep.ok(f"terms_hash recomputed: {computed}")


def check_evidence(job: dict, ev: dict, rep: Report) -> None:
    print("evidence bundle")
    errs = schema_errors(ev, EVIDENCE_SCHEMA)
    if errs:
        for e in errs:
            rep.fail(f"schema: {e}")
        return
    rep.ok("matches schema/evidence.schema.json")

    if ev["job_ref"] != job["job_ref"]:
        rep.fail(f"job_ref mismatch: {ev['job_ref']} != {job['job_ref']}")
    else:
        rep.ok("binds to the right job_ref")

    if ev["terms_hash"] != job.get("terms_hash"):
        rep.fail("terms_hash mismatch: evidence judged against different terms")
    else:
        rep.ok("binds to the same terms_hash")

    if ev["delivered_utc"] > job["deadline_utc"]:
        rep.warn(f"delivered at {ev['delivered_utc']}, after deadline {job['deadline_utc']}")

    have = {a["name"] for a in ev["artifacts"]}
    missing = [a["name"] for a in job["evidence_required"] if a["name"] not in have]
    if missing:
        rep.fail(f"missing required artifacts: {missing}")
    else:
        rep.ok(f"all {len(job['evidence_required'])} required artifacts present")

    for a in ev["artifacts"]:
        spec = next((r for r in job["evidence_required"] if r["name"] == a["name"]), None)
        if spec and a["bytes"] > spec.get("max_bytes", 10**12):
            rep.fail(f"artifact {a['name']} exceeds max_bytes")

    claims = {c["test_id"]: c for c in ev["claims"]}
    if len(claims) != len(ev["claims"]):
        rep.fail("duplicate claims for the same test id")
    known = {t["id"] for t in job["acceptance_tests"]}
    unknown = sorted(set(claims) - known)
    if unknown:
        rep.fail(f"claims for tests that do not exist: {unknown}")

    for t in job["acceptance_tests"]:
        if not t.get("mandatory", True):
            continue
        c = claims.get(t["id"])
        if c is None:
            rep.fail(f"mandatory test {t['id']} has no claim")
        elif c["result"] != "pass":
            rep.warn(f"mandatory test {t['id']} claimed {c['result']}")

    st = ev.get("settlement")
    if st:
        if st["payer"].lower() != job["buyer"].get("address", "").lower():
            rep.fail("settlement payer is not the job buyer")
        if st["payee"].lower() != job["seller"].get("address", "").lower():
            rep.fail("settlement payee is not the job seller")
        if st["amount_units"] != job["amount"]["units"]:
            rep.fail(f"settled {st['amount_units']} but job amount is {job['amount']['units']}")
        if st["confirmations"] == 0:
            rep.warn("settlement recorded with 0 confirmations")
        if not st["nonce"].startswith(job["job_ref"]):
            rep.warn("settlement nonce is not namespaced by job_ref: replay across jobs is possible")
        rep.ok("settlement fields present and structurally bound to this job")
    else:
        rep.warn("no settlement block: fine for a chain-escrowed job, not for an off-chain payment claim")

    signer = ev["seller_signer"]["address"]
    if signer.lower() != job["seller"].get("address", "").lower():
        rep.fail("evidence signed by an address that is not the seller")
    else:
        rep.ok("evidence signed by the seller address")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("job", type=Path)
    ap.add_argument("evidence", type=Path, nargs="?")
    ap.add_argument("--check-terms", action="store_true", help="recompute terms_hash with cast keccak")
    args = ap.parse_args()

    rep = Report()
    job = load(args.job)
    check_job(job, rep, args.check_terms)

    if args.evidence:
        ev = load(args.evidence)
        check_evidence(job, ev, rep)

    print()
    print(f"{len(rep.failures)} failures, {len(rep.warnings)} warnings")
    return 0 if not rep.failures else 1


if __name__ == "__main__":
    sys.exit(main())
