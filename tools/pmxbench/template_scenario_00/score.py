#!/usr/bin/env python3
"""PMxbench scorer (scenario-agnostic).

    python3 score.py submission.example.yaml
    python3 score.py --truth truth.yaml [--out scorecard.yaml] [--record DIR] submission.yaml

--truth defaults to the truth.yaml beside this script. Scores each item in [0, 1],
prints a scorecard, and writes scorecard.yaml next to the submission (or to --out).
Needs Python 3 and pyyaml.

Per-item scorers:
  numeric      relErr = |sub - exp| / |exp|; score = exp(-relErr / tol). 1 at zero
               error, ~0.37 at exactly 1x tol, decaying smoothly beyond. When
               exp == 0, tol is an absolute tolerance.
  categorical  1 if equal, else 0.
  set          F1 of submitted vs expected. Both empty -> 1; either empty -> 0.
               Decoys are absent from expected, so including one lowers precision.
  map          name -> value, names resolved through `aliases`, scored as numeric
               over the union of names; a missing or extra name scores 0.
  map_nested   param -> covariate -> value, flattened to param::cov, then as map.
               An effect on the wrong parameter or a decoy covariate scores 0.
  unanswered   key absent or null: 0, any scorer.
Items are averaged by weight within each pmx_area and overall.
provenance.analysis_steps is echoed, never scored.

--record DIR writes DIR/<slug>.yaml holding dataset, provenance and answers only,
for the private leaderboard. Scores are never stored; the leaderboard rescores.
"""
import argparse
import math
import random
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install pyyaml")


def _num(x):
    if isinstance(x, bool):
        return None
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def _str(x):
    """String form that matches across 62, 62.0 and "62"."""
    n = _num(x)
    if n is not None and n.is_integer():
        return str(int(n))
    return str(x)


def score_numeric(submitted, expected, tol):
    s = _num(submitted)
    if s is None:
        return 0.0
    rel = abs(s) if expected == 0 else abs(s - expected) / abs(expected)
    return math.exp(-rel / tol)


def score_categorical(submitted, expected):
    if submitted is None:
        return 0.0
    a, b = _num(submitted), _num(expected)
    if a is not None and b is not None:
        return float(a == b)
    return float(str(submitted) == str(expected))


def _as_list(x):
    if x is None:
        return []
    return list(x) if isinstance(x, (list, tuple)) else [x]


def score_set(submitted, expected):
    sub = [_str(x) for x in _as_list(submitted)]
    exp = [_str(x) for x in _as_list(expected)]
    if not sub and not exp:
        return 1.0
    if not sub or not exp:
        return 0.0
    tp = len(set(sub) & set(exp))
    p, r = tp / len(sub), tp / len(exp)
    return 0.0 if p + r == 0 else 2 * p * r / (p + r)


def _norm(x):
    return str(x).strip().lower()


def make_canon(aliases):
    lut = {}
    for cn, alts in (aliases or {}).items():
        for a in [cn] + list(alts or []):
            lut[_norm(a)] = _norm(cn)
    return lambda x: lut.get(_norm(x), _norm(x))


def _score_flat(sub_v, exp_v, tol):
    keys = set(exp_v) | set(sub_v)
    if not keys:
        return 1.0
    return sum(0.0 if k not in exp_v else score_numeric(sub_v.get(k), exp_v[k], tol)
               for k in keys) / len(keys)


def score_map(submitted, expected, tol, aliases=None):
    canon = make_canon(aliases)
    exp_v = {canon(k): v for k, v in (expected or {}).items()}
    sub_v = {canon(k): v for k, v in submitted.items()} if isinstance(submitted, dict) else {}
    return _score_flat(sub_v, exp_v, tol)


def score_map_nested(submitted, expected, tol, aliases=None):
    canon = make_canon(aliases)

    def flat(m):
        out = {}
        if isinstance(m, dict):
            for p, inner in m.items():
                if isinstance(inner, dict):
                    for cv, v in inner.items():
                        out[f"{canon(p)}::{canon(cv)}"] = v
        return out
    return _score_flat(flat(submitted), flat(expected), tol)


def _reported_names(sub_ans, nested):
    if not isinstance(sub_ans, dict):
        return []
    if not nested:
        return list(sub_ans)
    return [cv for inner in sub_ans.values() if isinstance(inner, dict) for cv in inner]


def score(truth, submission):
    """Score a submission dict against a truth dict. Returns the scorecard dict."""
    answers = submission.get("answers") or {}
    items, traps, unanswered = {}, [], []
    for it in truth["items"]:
        iid, sc = it["id"], it["scorer"]
        sub_ans = answers.get(iid)
        if sub_ans is None:
            unanswered.append(iid)
        if sc == "numeric":
            s = score_numeric(sub_ans, it["expected"], it["tol"])
        elif sc == "categorical":
            s = score_categorical(sub_ans, it["expected"])
        elif sc == "set":
            s = score_set(sub_ans, it["expected"])
        elif sc == "map":
            s = score_map(sub_ans, it["expected"], it["tol"], it.get("aliases"))
        elif sc == "map_nested":
            s = score_map_nested(sub_ans, it["expected"], it["tol"], it.get("aliases"))
        else:
            raise ValueError(f"unknown scorer {sc!r} for item {iid!r}")
        items[iid] = {"score": round(s, 4), "scorer": sc, "answered": sub_ans is not None,
                      "pmx_area": it["pmx_area"], "weight": it["weight"]}
        if it.get("decoys") and sub_ans is not None:
            reported = (_reported_names(sub_ans, sc == "map_nested") if sc in ("map", "map_nested")
                        else [_str(x) for x in _as_list(sub_ans)])
            decoys = {_norm(d) for d in it["decoys"]}
            hit = [n for n in dict.fromkeys(_norm(r) for r in reported) if n in decoys]
            if hit:
                traps.append(f"{iid}: decoy(s) included -> {', '.join(hit)}")

    def wmean(sel):
        return round(sum(x["weight"] * x["score"] for x in sel) / sum(x["weight"] for x in sel), 4)

    areas = list(dict.fromkeys(x["pmx_area"] for x in items.values()))
    return {
        "dataset": truth["meta"]["dataset"],
        "provenance": submission.get("provenance") or {},
        "items": items,
        "by_pmx_area": {a: wmean([x for x in items.values() if x["pmx_area"] == a]) for a in areas},
        "overall": wmean(list(items.values())),
        "unanswered_items": unanswered or "none",
        "traps_fallen_for": traps or "none detected",
    }


def _run_meta(sub_path):
    """run_meta.yaml written by the wrapper that ran the agent (baseline.sh), if any.
    Its harness, tool_sha and model are facts, so they override the self-report."""
    for c in (sub_path.parent.parent / "run_meta.yaml", sub_path.parent / "run_meta.yaml"):
        if c.exists():
            return yaml.safe_load(c.read_text()) or {}
    return {}


def _slug(x):
    x = re.sub(r"[^a-z0-9]+", "-", str(x or "").lower()).strip("-")
    return x or "unknown"


def main():
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description="Score a PMxbench submission.")
    ap.add_argument("submission")
    ap.add_argument("--truth", default=str(here / "truth.yaml"))
    ap.add_argument("--out", help="scorecard path (default: scorecard.yaml beside the submission)")
    ap.add_argument("--record", metavar="DIR", help="also store the run as DIR/<slug>.yaml")
    a = ap.parse_args()

    sub_path = Path(a.submission).resolve()
    truth = yaml.safe_load(Path(a.truth).read_text())
    sub = yaml.safe_load(sub_path.read_text()) or {}
    prov = dict(sub.get("provenance") or {})
    meta = _run_meta(sub_path)
    for k in ("harness", "tool_sha"):
        if meta.get(k):
            prov[k] = meta[k]
    if meta.get("model"):
        prov["model"] = meta["model"]
    if meta.get("env"):
        prov["env"] = meta["env"]
    sub["provenance"] = prov
    sc = score(truth, sub)

    print("===== PMxbench scorecard =====")
    print("dataset:", sc["dataset"])
    print(f"tool: {prov.get('tool')}   harness: {prov.get('harness', 'unknown')}   "
          f"model: {prov.get('model')}   run: {prov.get('run_utc')}")
    print("\n-- item scores --")
    for iid, x in sc["items"].items():
        flag = "" if x["answered"] else "  (unanswered)"
        print(f"  {iid:<18} {x['score']:.3f}  [{x['scorer']}, {x['pmx_area']}]{flag}")
    print("\n-- by pmx_area --")
    for k, v in sc["by_pmx_area"].items():
        print(f"  {k:<20} {v:.3f}")
    print(f"\noverall: {sc['overall']:.3f}")
    traps = sc["traps_fallen_for"]
    print("\ntraps fallen for:")
    for t in ([traps] if isinstance(traps, str) else traps):
        print("  -", t)

    out = Path(a.out) if a.out else sub_path.parent / "scorecard.yaml"
    out.write_text(yaml.safe_dump(sc, sort_keys=False, allow_unicode=True))
    print("\nscorecard written to", out)

    if a.record:
        ts = re.sub(r"[^0-9TZ]", "", str(prov.get("run_utc") or "")) or \
            datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        slug = "__".join([_slug(sc["dataset"]), _slug(prov.get("tool")), _slug(prov.get("harness")),
                          _slug(prov.get("model")), ts, f"{random.randrange(16 ** 6):06x}"])
        keep = ["tool", "harness", "model", "harness_version", "software", "tool_sha",
                "run_utc", "env", "analysis_steps"]
        entry = {"dataset": sc["dataset"], "provenance": {k: prov[k] for k in keep if k in prov},
                 "answers": sub.get("answers")}
        d = Path(a.record)
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{slug}.yaml").write_text(yaml.safe_dump(entry, sort_keys=False, allow_unicode=True))
        print("recorded to", d / f"{slug}.yaml")


if __name__ == "__main__":
    main()
