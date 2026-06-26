#!/usr/bin/env python3
"""Render a standalone HTML results slide for a PMbench run.

Fully deterministic: every element is computed from the loop's own artifacts,
with no hand-authored prose layer. The same inputs always render the same slide.

Inputs, all produced by a normal proctor -> run -> score loop:

  --scorecard  scorecard.yaml written by score.R (item scores, pmx areas,
               weights, overall, provenance). Authoritative for every number
               that gets scored; also supplies the title/subtitle text.
  --truth      the scenario's held-out truth.yaml. Optional. When given, the
               trap ledger (right column) is DERIVED from the contract: every
               `set`-scorer item becomes a trap (decoys excluded? expected set
               recovered?). Scenario-agnostic -- no item ids are hardcoded.
  --submission the run's submission.yaml. Optional; pairs with --truth to give
               per-trap verdicts. Without it, traps render as "not submitted".
  --log        the Modus run_*.log (stream-json). Optional. Parsed for the
               per-task KPIs that never reach the scorecard: wall-clock, cost,
               and the per-task timeline.

Omit any optional input and its section simply drops out. No external state,
no answer-key results ever live in a separate file beside the slide.

Usage:
  python visualize_results.py --scorecard SC.yaml [--truth truth.yaml] \
      [--submission submission.yaml] [--log run.log] [--out slide.html]
"""
import argparse
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install pyyaml")


# ---------------------------------------------------------------- log parsing
def parse_log(path):
    """Pull per-task KPIs from a Modus stream-json log.

    Each task is one fresh agent spawn, so the loop emits exactly one `result`
    event per task, in task order. We zip those against the scorecard's
    analysis_steps for labels.
    """
    results = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("type") == "result":
            results.append(e)
    tasks = []
    for e in results:
        tasks.append({
            "wall_s": e.get("duration_ms", 0) / 1000,
            "turns": e.get("num_turns", 0),
            "cost": e.get("total_cost_usd", 0) or 0,
            "out_tokens": e.get("usage", {}).get("output_tokens", 0),
        })
    return tasks


def fmt_minutes(seconds):
    m = seconds / 60
    return f"{m:.0f} min" if m >= 1 else f"{seconds:.0f}s"


# ------------------------------------------------------- deterministic traps
def _norm_set(v):
    """A truth/submission set field -> a set of trimmed strings."""
    if v is None:
        return set()
    if not isinstance(v, (list, tuple)):
        v = [v]
    return {str(x).strip() for x in v}


def _sorted_vals(s):
    """Sort a set of string values numerically when they are all ints, else
    lexically -- so ROWIDs read 62, 692, 1322 and names read A, B, C."""
    vals = list(s)
    try:
        return sorted(vals, key=int)
    except ValueError:
        return sorted(vals)


def _item_names(scorer, value):
    """The set of names a submitted/expected answer contributes for trap
    watching, by scorer. For `set`, the elements themselves; for `map`, the
    top-level keys; for `map_nested`, the leaf (second-level) keys -- e.g. the
    covariate names under each parameter. Mirrors score.R's trap watching, so a
    decoy is caught wherever it is reported."""
    if value is None:
        return set()
    if scorer == "set":
        return _norm_set(value)
    # map keys are matched case-insensitively (as score.R canonicalizes names),
    # so lowercase here; trap captions still print the decoy from truth verbatim.
    if scorer == "map":
        return {str(k).strip().lower() for k in value} if isinstance(value, dict) else set()
    if scorer == "map_nested":
        names = set()
        if isinstance(value, dict):
            for inner in value.values():
                if isinstance(inner, dict):
                    names |= {str(k).strip().lower() for k in inner}
        return names
    return set()


def derive_traps(truth, submission):
    """Compute the trap ledger from the contract -- scenario-agnostic.

    Driven entirely by the generic truth.yaml schema, not by specific item ids:
    any `set`-scorer item yields a trap, so a new scenario gets a ledger with no
    code change here. The logic is the same set comparison score.R uses:

      * a set item WITH `decoys`  -> one trap per decoy (was it excluded?) plus
        a "real positives recovered" trap (did the run find `expected`?).
      * a set item WITHOUT decoys -> one completeness trap (submitted ==
        expected?).

    Captions are generic but factual (they name the actual values, never an
    interpretation). Trap names are the truth item's own `id` -- the same key
    score.R prints -- so the slide and the scorecard speak the same language.

    Each returned trap is {name, ok, caption}; `ok` is True/False/None
    (unanswered) and drives the marker and color. Traps the contract cannot
    express -- e.g. the allometric exponent and BLQ, folded into the cl/vc
    numeric tolerance per truth.yaml -- are deliberately not invented here.
    """
    if not truth:
        return []
    sub = (submission or {}).get("answers", {}) if submission else {}
    traps = []

    for item in truth.get("items", []):
        scorer = item.get("scorer")
        # set items yield a completeness or decoy ledger; map / map_nested items
        # yield a decoy ledger only (their numeric accuracy is the score's job,
        # not a pass/fail trap). Other scorers contribute no traps.
        if scorer not in ("set", "map", "map_nested"):
            continue
        iid = item.get("id")
        if not iid:
            continue
        decoys = _norm_set(item.get("decoys"))

        if scorer == "set":
            expected = _norm_set(item.get("expected"))
            submitted = _norm_set(sub.get(iid)) if iid in sub else None
            noun = "item" + ("s" if len(expected) != 1 else "")
        else:
            # map / map_nested: compare by reported names, not values.
            expected = _item_names(scorer, item.get("expected"))
            submitted = _item_names(scorer, sub.get(iid)) if iid in sub else None

        if decoys:
            # Recovery of the true positives, then one trap per decoy.
            if submitted is None:
                ok, why = None, f"{iid}: not submitted"
            elif expected <= submitted:
                ok, why = True, f"{', '.join(_sorted_vals(expected))} correctly identified"
            else:
                missing = expected - submitted
                ok, why = False, f"missed {', '.join(_sorted_vals(missing))}"
            traps.append({"name": f"{iid}: true positives", "ok": ok, "caption": why})

            for decoy in _sorted_vals(decoys):
                # map name-sets are lowercased; set elements are verbatim. Test
                # membership accordingly so a decoy is caught regardless of case.
                present = (decoy.lower() if scorer != "set" else decoy) in submitted
                if submitted is None:
                    ok, why = None, "not assessed"
                elif present:
                    ok, why = False, f"{decoy} wrongly reported (it is a decoy / true negative)"
                else:
                    ok, why = True, f"{decoy} correctly excluded as a decoy"
                traps.append({"name": f"{decoy} decoy", "ok": ok, "caption": why})
        elif scorer == "set":
            # No decoys: a single completeness check against expected.
            if submitted is None:
                ok, why = None, f"{iid}: not submitted"
            elif submitted == expected:
                ok, why = True, f"all {len(expected)} expected {noun} matched ({', '.join(_sorted_vals(expected))})"
            else:
                missed = expected - submitted
                extra = submitted - expected
                parts = []
                if missed:
                    parts.append(f"missed {', '.join(_sorted_vals(missed))}")
                if extra:
                    parts.append(f"false-flagged {', '.join(_sorted_vals(extra))}")
                ok, why = False, "; ".join(parts)
            traps.append({"name": iid, "ok": ok, "caption": why})

    return traps


# --------------------------------------------------------------- html helpers
def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;"))


def score_class(score):
    return "full" if score >= 0.999 else ""


def area_class(pct):
    return "perfect" if pct >= 0.999 else ("soft" if pct < 0.9 else "")


def render(scorecard, tasks, traps):
    items = scorecard.get("items", {})
    areas = scorecard.get("by_pmx_area", {})
    overall = scorecard.get("overall", 0)
    prov = scorecard.get("provenance", {})
    # Headline trap status: prefer the derived ledger; fall back to scorecard.
    if traps:
        clean = all(t["ok"] for t in traps if t["ok"] is not None)
    else:
        sc_status = str(scorecard.get("traps_fallen_for", "")).strip()
        clean = sc_status.lower() in ("none detected", "none", "")
    n_bitten = sum(1 for t in traps if t["ok"] is False)

    # Header text is derived from the scorecard's provenance -- no hand-authored
    # layer, so nothing here can carry a held-out result into the slide.
    n_steps = len(prov.get("analysis_steps", []))
    subtitle = (f"{esc(prov.get('tool',''))} · {esc(prov.get('model',''))} · "
                f"{n_steps} tasks, headless")
    title = f"PMbench · {esc(scorecard.get('dataset', 'run'))}"

    # ---- KPI strip (only if we have a log) ----
    kpis_html = ""
    timeline_html = ""
    if tasks:
        total_wall = sum(t["wall_s"] for t in tasks)
        total_cost = sum(t["cost"] for t in tasks)
        total_turns = sum(t["turns"] for t in tasks)
        n_tasks = len(prov.get("analysis_steps", [])) or len(tasks)
        cost_str = f"${total_cost:.2f}" if total_cost else "—"
        kpis_html = f"""
  <div class="kpis">
    <div class="kpi"><div class="v">{fmt_minutes(total_wall)}</div><div class="k">wall clock</div></div>
    <div class="kpi"><div class="v">{cost_str}</div><div class="k">total cost</div></div>
    <div class="kpi"><div class="v">{total_turns}</div><div class="k">agent turns</div></div>
    <div class="kpi"><div class="v ok">{len(tasks)} / {n_tasks}</div><div class="k">tasks passed</div></div>
    <div class="kpi"><div class="v {'ok' if clean else ''}">{'0' if clean else '!'}</div><div class="k">traps · failures</div></div>
  </div>"""

        # ---- timeline ----
        labels = prov.get("analysis_steps", []) or [f"task {i+1}" for i in range(len(tasks))]
        max_wall = max((t["wall_s"] for t in tasks), default=1)
        rows = []
        for label, t in zip(labels, tasks):
            pct = 100 * t["wall_s"] / max_wall
            hot = "hot" if t["wall_s"] >= 0.999 * max_wall else ""
            cost_str = f"${t['cost']:.2f}" if t["cost"] else "—"
            rows.append(
                f'    <div class="tl-row"><div class="tl-name">{esc(label)}</div>'
                f'<div class="tl-bar-wrap"><div class="tl-bar {hot}" style="width:{pct:.1f}%"></div></div>'
                f'<div class="tl-meta">{t["wall_s"]/60:.1f} min · {cost_str}</div></div>')
        timeline_html = f"""
  <div class="timeline">
    <h2>Per-task timeline · {fmt_minutes(total_wall)} total, fresh agent each</h2>
{chr(10).join(rows)}
  </div>"""

    # ---- item bars ----
    item_rows = []
    for key, it in items.items():
        sc = it.get("score", 0)
        tag = f"{it.get('scorer','')} · {it.get('pmx_area','')}"
        item_rows.append(
            f'      <div class="item">\n'
            f'        <div class="row"><div><span class="name">{esc(key)}</span>'
            f'<span class="tag">{esc(tag)}</span></div><div class="val">{sc:.3f}</div></div>\n'
            f'        <div class="track"><div class="fill {score_class(sc)}" style="width:{sc*100:.1f}%"></div></div>\n'
            f'      </div>')

    # ---- area cards ----
    area_cards = []
    for name, pct in areas.items():
        short = name.replace("covariate-analysis", "covariate")
        area_cards.append(
            f'        <div class="area {area_class(pct)}"><div class="ttl">{esc(short)}</div>'
            f'<div class="pct">{pct:.2f}</div></div>')

    # ---- traps (derived from truth + submission) ----
    trap_rows = []
    for t in traps:
        if t["ok"] is None:
            mark, cls = "•", "trap unknown"
        elif t["ok"]:
            mark, cls = "✓", "trap"
        else:
            mark, cls = "✗", "trap bitten"
        trap_rows.append(
            f'        <li class="{cls}"><div class="chk">{mark}</div><div class="txt">'
            f'<b>{esc(t["name"])}</b><span>{esc(t["caption"])}</span></div></li>')
    # The right column holds only the trap ledger; with no traps (e.g. no
    # --truth given) drop it and collapse the body to a single column rather
    # than leaving a lopsided empty half.
    if trap_rows:
        hdr = "none fallen for" if clean else f"{n_bitten} fallen for"
        traps_block = (f'      <h2>Traps — {hdr}</h2>\n'
                       f'      <ul class="traps">\n{chr(10).join(trap_rows)}\n      </ul>')
        right_col = f'    <div class="col right">\n{traps_block}\n    </div>'
        body_class = ""
    else:
        right_col = ""
        body_class = " solo"

    clean_badge = "0 TRAPS BITTEN" if clean else f"{n_bitten} TRAP{'S' if n_bitten != 1 else ''} BITTEN"
    footer = "proctor → run → score · scored against held-out truth.yaml outside the loop"

    return TEMPLATE.format(
        title=esc(title), subtitle=subtitle, overall=f"{overall:.3f}",
        kpis=kpis_html, items="\n".join(item_rows),
        areas="\n".join(area_cards), right_col=right_col, body_class=body_class,
        timeline=timeline_html, footer=esc(footer), clean_badge=clean_badge)


TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title}</title>
<style>
  :root{{
    --bg:#0d1117; --panel:#161b22; --ink:#e6edf3; --muted:#8b949e; --line:#30363d;
    --good:#3fb950; --warn:#d29922; --accent:#58a6ff; --accent2:#a371f7;
  }}
  *{{box-sizing:border-box;margin:0;padding:0}}
  body{{background:radial-gradient(1200px 700px at 80% -10%, #14233b 0%, var(--bg) 55%);
    color:var(--ink); font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,Helvetica,Arial,sans-serif;
    display:flex; align-items:center; justify-content:center; padding:32px; min-height:100vh;}}
  .slide{{width:1120px; max-width:100%; background:linear-gradient(180deg,#11161e 0%, #0e131b 100%);
    border:1px solid var(--line); border-radius:20px; box-shadow:0 24px 80px rgba(0,0,0,.55); overflow:hidden;}}
  .head{{display:flex; align-items:flex-end; justify-content:space-between; padding:26px 36px 20px;
    border-bottom:1px solid var(--line); background:linear-gradient(90deg, rgba(88,166,255,.08), rgba(163,113,247,.06));}}
  .head h1{{font-size:26px; font-weight:700; letter-spacing:.2px}}
  .sub{{margin-top:6px; color:var(--muted); font-size:13px; font-family:ui-monospace,SFMono-Regular,Menlo,monospace}}
  .score-badge{{text-align:right}}
  .score-badge .num{{font-size:54px; font-weight:800; line-height:1;
    background:linear-gradient(90deg,var(--good),#7ee787); -webkit-background-clip:text; background-clip:text; color:transparent}}
  .score-badge .lbl{{color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:1.5px; margin-top:4px}}
  .kpis{{display:flex; border-bottom:1px solid var(--line); background:#0c1117}}
  .kpi{{flex:1; padding:14px 0 13px; text-align:center; border-right:1px solid var(--line)}}
  .kpi:last-child{{border-right:none}}
  .kpi .v{{font-size:20px; font-weight:800; font-variant-numeric:tabular-nums; letter-spacing:.3px}}
  .kpi .v.ok{{color:var(--good)}}
  .kpi .k{{font-size:10.5px; color:var(--muted); text-transform:uppercase; letter-spacing:1.2px; margin-top:3px}}
  .body{{display:grid; grid-template-columns:1.35fr 1fr; gap:0}}
  .body.solo{{grid-template-columns:1fr}}
  .body.solo .col.left{{border-right:none}}
  .col{{padding:24px 30px}}
  .col.left{{border-right:1px solid var(--line)}}
  .col h2{{font-size:12px; text-transform:uppercase; letter-spacing:1.6px; color:var(--muted); margin-bottom:15px; font-weight:600}}
  .item{{margin-bottom:13px}}
  .item .row{{display:flex; justify-content:space-between; align-items:baseline; margin-bottom:5px}}
  .item .name{{font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:13.5px}}
  .item .tag{{color:var(--muted); font-size:11px; margin-left:8px}}
  .item .val{{font-variant-numeric:tabular-nums; font-weight:700; font-size:14px}}
  .track{{height:9px; background:#222b38; border-radius:6px; overflow:hidden}}
  .fill{{height:100%; border-radius:6px; background:linear-gradient(90deg,var(--accent),var(--accent2))}}
  .fill.full{{background:linear-gradient(90deg,var(--good),#7ee787)}}
  .areas{{display:flex; gap:10px; margin-top:4px}}
  .area{{flex:1; background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:12px 13px}}
  .area .ttl{{font-size:10.5px; color:var(--muted); letter-spacing:.3px; line-height:1.2}}
  .area .pct{{font-size:22px; font-weight:800; margin-top:5px; font-variant-numeric:tabular-nums}}
  .area.perfect .pct{{color:var(--good)}}
  .area.soft .pct{{color:var(--warn)}}
  .traps{{list-style:none; display:flex; flex-direction:column; gap:9px; margin-top:2px}}
  .trap{{display:flex; gap:11px; align-items:flex-start; background:var(--panel);
    border:1px solid var(--line); border-left:3px solid var(--good); border-radius:10px; padding:10px 12px}}
  .trap .chk{{color:var(--good); font-weight:800; font-size:15px; line-height:1.3}}
  .trap .txt b{{font-size:12.5px}}
  .trap .txt span{{display:block; color:var(--muted); font-size:11px; margin-top:2px; line-height:1.4}}
  .trap.bitten{{border-left-color:#f85149}}
  .trap.bitten .chk{{color:#f85149}}
  .trap.unknown{{border-left-color:var(--muted)}}
  .trap.unknown .chk{{color:var(--muted)}}
  .timeline{{padding:18px 36px 6px; border-top:1px solid var(--line)}}
  .timeline h2{{font-size:12px; text-transform:uppercase; letter-spacing:1.6px; color:var(--muted); margin-bottom:13px; font-weight:600}}
  .tl-row{{display:flex; align-items:center; gap:12px; margin-bottom:7px}}
  .tl-name{{width:148px; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:12px; text-align:right}}
  .tl-bar-wrap{{flex:1; height:18px; background:#161b22; border-radius:5px; overflow:hidden}}
  .tl-bar{{height:100%; border-radius:5px; background:linear-gradient(90deg,#1f6feb,#388bfd)}}
  .tl-bar.hot{{background:linear-gradient(90deg,#bb8009,#d29922)}}
  .tl-meta{{width:130px; font-size:11px; color:var(--muted); font-variant-numeric:tabular-nums; font-family:ui-monospace,SFMono-Regular,Menlo,monospace}}
  .foot{{display:flex; justify-content:space-between; align-items:center; padding:14px 36px 18px;
    color:var(--muted); font-size:11.5px; font-family:ui-monospace,SFMono-Regular,Menlo,monospace}}
  .clean{{color:var(--good); font-weight:700; letter-spacing:.4px}}
</style>
</head>
<body>
<div class="slide">
  <div class="head">
    <div>
      <h1>{title}</h1>
      <div class="sub">{subtitle}</div>
    </div>
    <div class="score-badge">
      <div class="num">{overall}</div>
      <div class="lbl">overall score</div>
    </div>
  </div>
{kpis}
  <div class="body{body_class}">
    <div class="col left">
      <h2>Item scores</h2>
{items}
      <h2 style="margin-top:22px">By pharmacometric area</h2>
      <div class="areas">
{areas}
      </div>
    </div>
{right_col}
  </div>
{timeline}
  <div class="foot">
    <div class="prov">{footer}</div>
    <div class="clean">{clean_badge}</div>
  </div>
</div>
</body>
</html>
"""


def main():
    ap = argparse.ArgumentParser(description="Render a PMbench results slide.")
    ap.add_argument("--scorecard", required=True, help="scorecard.yaml from score.R")
    ap.add_argument("--truth", help="held-out truth.yaml; enables the derived trap ledger")
    ap.add_argument("--submission", help="run submission.yaml; pairs with --truth for verdicts")
    ap.add_argument("--log", help="Modus run_*.log for KPIs + timeline (optional)")
    ap.add_argument("--out", default="results_slide.html", help="output HTML path")
    args = ap.parse_args()

    scorecard = yaml.safe_load(Path(args.scorecard).read_text())
    tasks = parse_log(args.log) if args.log else []
    truth = yaml.safe_load(Path(args.truth).read_text()) if args.truth else None
    submission = yaml.safe_load(Path(args.submission).read_text()) if args.submission else None
    traps = derive_traps(truth, submission)

    html = render(scorecard, tasks, traps)
    Path(args.out).write_text(html)
    bitten = sum(1 for t in traps if t["ok"] is False)
    print(f"Wrote {args.out}  ·  overall {scorecard.get('overall')}  ·  "
          f"{len(traps)} traps derived ({bitten} bitten)  ·  "
          f"{len(tasks)} tasks from log")


if __name__ == "__main__":
    main()
