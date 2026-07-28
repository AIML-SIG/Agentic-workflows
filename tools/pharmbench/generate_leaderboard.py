#!/usr/bin/env python3
"""Regenerate the leaderboard page from tools/pharmbench/results/<run>/.

Reads every recorded run (a `results/<slug>/scorecard.yaml`, written by
`score.R --record`, alongside its `submission.yaml`), groups by the
configuration that actually matters for comparability -- scenario, tool,
harness, and model (see `group_key`; deliberately excludes tool_sha /
pharmbench_sha, which are whole-monorepo HEAD SHAs and churn on unrelated
commits) -- and computes n/mean/sd/min/max of the overall score (and each
pmx_area) within each group. Repeated attempts of the identical
configuration land in the same group, which is where the variance comes
from.

Also (re)renders each run's drill-down slide via `visualize_results.py`, from
its scorecard + submission + the scenario's truth.yaml (no raw agent log --
see `score.R`'s record block for why those aren't archived), and links it
from the "Individual runs" table.

A manually curated `results/failed_runs.yaml`, if present, lists known runs
that never produced a submission (so score.R had nothing to score); its
counts feed a "Failed" column on the main table and a "Known failed
attempts" detail section.

provenance.cost_usd (written by baseline.sh/run.sh into run_meta.yaml, see
those scripts for how each harness's cost is computed) feeds a "Cost"
column, mean/sd'd like the score itself; absent for harnesses or older runs
where it isn't available.

Output is a static Quarto page (docs/leaderboard.qmd) -- plain markdown, no
live code execution required to render it, since this repo's devcontainer
doesn't set up Quarto's R/Python execution engines.

Usage:
  python3 generate_leaderboard.py [--results DIR] [--out docs/leaderboard.qmd]
                                   [--exclude-dataset DATASET ...]
                                   [--no-individual-runs]
"""
import argparse
import math
import statistics
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install pyyaml")

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent


def short(sha):
    if not sha or sha in ("unknown", "0000000"):
        return "unknown"
    return str(sha)[:12]


# The same model shows up under different strings depending on how it was
# captured: run_meta.yaml (baseline.sh/run.sh) records the raw --model CLI
# flag verbatim ("sonnet"), which score.R treats as more trustworthy than an
# agent's self-reported provenance.model ("claude-sonnet-5") -- so every
# *future* run for a given model lands on the short alias, while runs
# recorded before that override existed may still carry a longer resolved
# name. Canonicalize toward the short alias (what new runs will always use)
# so they group together instead of silently fragmenting the leaderboard.
# Extend this as new mismatches turn up, same as truth.yaml's `aliases:`
# blocks for parameter names.
MODEL_ALIASES = {
    "claude-sonnet-5": "sonnet",
}


def canon_model(model):
    return MODEL_ALIASES.get(model, model)


def truth_path_for(dataset):
    """`pmb-<scenario-id>` -> scenarios/<scenario-id>/evals/truth.yaml."""
    scenario_id = dataset[len("pmb-"):] if dataset.startswith("pmb-") else dataset
    path = SCRIPT_DIR / "scenarios" / scenario_id / "evals" / "truth.yaml"
    return path if path.exists() else None


def load_failed(results_dir):
    """Manually curated results/failed_runs.yaml -- runs that never produced
    a submission.yaml, so score.R had nothing to score and they never land
    in results/ the normal way. Matched onto leaderboard rows by
    (dataset, tool, harness, model); absent file/empty list is fine."""
    path = results_dir / "failed_runs.yaml"
    if not path.exists():
        return []
    with open(path) as fh:
        entries = yaml.safe_load(fh) or []
    for e in entries:
        e.setdefault("count", 1)
        e["model"] = canon_model(e["model"])
    return entries


def failed_key(e):
    return (e["dataset"], e["tool"], e["harness"], e["model"])


def render_slide(run_dir, scorecard_path, submission_path, truth_path):
    """Render this run's drill-down slide via visualize_results.py. No --log:
    raw agent logs aren't archived (see score.R), so the slide's trap ledger
    and score breakdown are populated but its wall-clock/cost timeline is
    not. Returns True on success."""
    slide_path = run_dir / "slide.html"
    cmd = [sys.executable, str(SCRIPT_DIR / "visualize_results.py"),
           "--scorecard", str(scorecard_path), "--out", str(slide_path)]
    if truth_path:
        cmd += ["--truth", str(truth_path)]
    if submission_path.exists():
        cmd += ["--submission", str(submission_path)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  slide render failed for {run_dir.name}: {result.stderr.strip()}",
              file=sys.stderr)
        return False
    return True


def load_records(results_dir):
    records = []
    for f in sorted(results_dir.glob("*/scorecard.yaml")):
        run_dir = f.parent
        with open(f) as fh:
            sc = yaml.safe_load(fh)
        prov = sc.get("provenance", {}) or {}
        dataset = sc.get("dataset", "unknown")
        submission_path = run_dir / "submission.yaml"
        has_slide = render_slide(run_dir, f, submission_path, truth_path_for(dataset))
        records.append({
            "run_dir": run_dir.name,
            "slide": "slide.html" if has_slide else None,
            "dataset": dataset,
            "tool": prov.get("tool", "unknown"),
            "tool_sha": short(prov.get("tool_sha")),
            "pharmbench_sha": short(prov.get("pharmbench_sha")),
            "harness": prov.get("harness") or "unknown",
            "model": canon_model(prov.get("model", "unknown")),
            "run_utc": prov.get("run_utc", ""),
            "overall": sc.get("overall"),
            "by_pmx_area": sc.get("by_pmx_area", {}) or {},
            "cost_usd": cost_float(prov.get("cost_usd")),
            "duration_s": int_or_none(prov.get("duration_s")),
        })
    return records


def cost_float(cost_usd):
    try:
        return float(cost_usd) if cost_usd not in (None, "") else None
    except (TypeError, ValueError):
        return None


def int_or_none(x):
    try:
        return int(x) if x not in (None, "") else None
    except (TypeError, ValueError):
        return None


def fmt_duration(seconds):
    if seconds is None:
        return "—"
    m, s = divmod(int(round(seconds)), 60)
    h, m = divmod(m, 60)
    if h:
        return f"{h}h{m:02d}m"
    return f"{m}m{s:02d}s"


def group_key(r):
    # Deliberately excludes tool_sha/pharmbench_sha: both are `git rev-parse
    # HEAD` of the whole monorepo (see baseline.sh/run.sh and score.R), not
    # scoped to the tool's own files, so any unrelated commit elsewhere in
    # the repo bumps them -- they'd fragment the leaderboard on repo churn
    # that has nothing to do with the tool actually changing. Still visible
    # per-run in the "Individual runs" table for full traceability.
    return (r["dataset"], r["tool"], r["harness"], r["model"])


def stats(values):
    values = [v for v in values if v is not None]
    n = len(values)
    if n == 0:
        return {"n": 0, "mean": None, "sd": None, "min": None, "max": None}
    return {
        "n": n,
        "mean": round(statistics.mean(values), 4),
        "sd": round(statistics.stdev(values), 4) if n > 1 else None,
        "min": round(min(values), 4),
        "max": round(max(values), 4),
    }


def fmt(x, digits=3):
    return "—" if x is None else f"{x:.{digits}f}"


def fmt_cost(x):
    return "—" if x is None else f"${x:.2f}"


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;"))


def nice_ceil(x):
    """Round x up to a "nice" axis-max (1/2/2.5/5/10 x 10^n) -- avoids
    charts that top out at an ugly value like 8.37 or 143."""
    if x is None or x <= 0:
        return 1.0
    exp = math.floor(math.log10(x))
    base = x / (10 ** exp)
    for cand in (1, 2, 2.5, 5, 10):
        if base <= cand:
            return cand * (10 ** exp)
    return 10 * (10 ** exp)


def fmt_tick_duration(seconds):
    total_min = round(seconds / 60)
    h, m = divmod(total_min, 60)
    if h:
        return f"{h}h{m:02d}m" if m else f"{h}h"
    return f"{m}m"


# Bar/tool color assignment for the score/cost/duration charts. Only two
# tools exist today (modus, baseline); a third would need a third slot from
# the same validated categorical ordering in palette.md rather than an
# arbitrary hue.
TOOL_COLORS = {
    "modus": "#2a78d6",     # categorical slot 1 (blue)
    "baseline": "#1baf7a",  # categorical slot 2 (aqua)
}
TOOL_COLOR_FALLBACK = "#eda100"  # slot 3 (yellow), if a third tool appears


def _h_bar_path(x0, y, w, h, r):
    """Horizontal bar growing right from x0: flat at the baseline (left),
    rounded on the data-end (right) per the mark spec -- never round all
    four corners of a bar anchored to an axis."""
    if w <= 0:
        return ""
    r = min(r, h / 2, w)
    return (f"M{x0},{y} H{x0 + w - r} "
            f"A{r},{r} 0 0 1 {x0 + w},{y + r} "
            f"V{y + h - r} "
            f"A{r},{r} 0 0 1 {x0 + w - r},{y + h} "
            f"H{x0} Z")


def render_config_charts(dataset, recs):
    """Small-multiples SVG: Score / Cost / Duration bar charts, one bar per
    (tool, harness, model) config, same row order and color-by-tool across
    all three panels so a config lines up visually across metrics.

    Deliberately NOT a dual-axis chart -- score (0-1), cost ($), and
    duration (wall-clock) live on incompatible scales, so overlaying them
    on shared axes would invite a false visual correlation. Three panels
    with their own correctly-scaled axis do the same comparison job without
    that risk (see the dataviz skill's anti-patterns doc).
    """
    recs = [r for r in recs if r["n_runs"] > 0]
    if not recs:
        return ""
    recs = sorted(recs, key=lambda r: -(r["overall"]["mean"] or 0))

    LABEL_W, PLOT_W, VAL_W = 172, 240, 74
    ROW_H, BAR_H, TITLE_H, AXIS_H = 30, 18, 28, 26
    PANEL_W = LABEL_W + PLOT_W + VAL_W
    n = len(recs)
    PANEL_H = TITLE_H + n * ROW_H + AXIS_H
    x0 = LABEL_W

    def panel(title, get, fmt_val, fmt_tick, domain_hint, value_cap=None):
        # value_cap bounds both the domain and the whisker to a hard ceiling
        # a metric can't exceed (score maxes at 1.0) -- without it, a run
        # whose mean+sd overshoots that ceiling by a hair (sd is an
        # unconstrained sample statistic, unlike the score itself) would
        # push nice_ceil to the next round number and waste half the panel.
        stats_list = [get(r) for r in recs]
        highs = [min(s["mean"] + (s["sd"] or 0), value_cap) if value_cap is not None
                 else s["mean"] + (s["sd"] or 0)
                 for s in stats_list if s["mean"] is not None]
        domain_max = nice_ceil(max(highs + [domain_hint])) if highs else domain_hint
        if value_cap is not None:
            domain_max = min(domain_max, value_cap)
        ticks = [domain_max * i / 4 for i in range(5)]

        svg = [f'<svg viewBox="0 0 {PANEL_W} {PANEL_H}" width="100%" '
               f'height="{PANEL_H}" role="img" aria-label="{esc(title)} by configuration">']
        svg.append(f'<text x="0" y="18" class="pmb-c-title">{esc(title)}</text>')

        plot_bottom = TITLE_H + n * ROW_H
        # gridlines + tick labels
        for t in ticks:
            gx = x0 + PLOT_W * (t / domain_max if domain_max else 0)
            svg.append(f'<line x1="{gx:.1f}" y1="{TITLE_H}" x2="{gx:.1f}" '
                       f'y2="{plot_bottom}" class="pmb-c-grid" />')
            svg.append(f'<text x="{gx:.1f}" y="{plot_bottom + 16}" '
                       f'class="pmb-c-tick" text-anchor="middle">{esc(fmt_tick(t))}</text>')
        svg.append(f'<line x1="{x0}" y1="{TITLE_H}" x2="{x0}" y2="{plot_bottom}" class="pmb-c-axis" />')

        for i, r in enumerate(recs):
            v = get(r)
            yc = TITLE_H + i * ROW_H + ROW_H / 2
            bar_y = yc - BAR_H / 2
            color = TOOL_COLORS.get(r["tool"], TOOL_COLOR_FALLBACK)
            label = f'{r["tool"]} · {r["harness"]} {r["model"]}'
            svg.append(f'<text x="{x0 - 8}" y="{yc:.1f}" class="pmb-c-label" '
                       f'text-anchor="end" dominant-baseline="middle">{esc(label)}</text>')
            if v["mean"] is None:
                continue
            frac = v["mean"] / domain_max if domain_max else 0
            bar_w = PLOT_W * frac
            path = _h_bar_path(x0, bar_y, bar_w, BAR_H, 4)
            tip = f'{label}: {fmt_val(v["mean"])} (n={v["n"]})'
            svg.append(f'<path d="{path}" fill="{color}">'
                       f'<title>{esc(tip)}</title></path>')
            label_end_x = x0 + bar_w
            if v["sd"] is not None:
                lo = max(0, v["mean"] - v["sd"])
                hi = v["mean"] + v["sd"]
                if value_cap is not None:
                    hi = min(hi, value_cap)
                lx = x0 + PLOT_W * (lo / domain_max if domain_max else 0)
                hx = x0 + PLOT_W * (hi / domain_max if domain_max else 0)
                svg.append(f'<line x1="{lx:.1f}" y1="{yc:.1f}" x2="{hx:.1f}" y2="{yc:.1f}" class="pmb-c-whisker" />')
                svg.append(f'<line x1="{lx:.1f}" y1="{yc - 4:.1f}" x2="{lx:.1f}" y2="{yc + 4:.1f}" class="pmb-c-whisker" />')
                svg.append(f'<line x1="{hx:.1f}" y1="{yc - 4:.1f}" x2="{hx:.1f}" y2="{yc + 4:.1f}" class="pmb-c-whisker" />')
                # The label anchors past whichever extends further right -- the
                # bar tip or the whisker's high cap -- so a wide sd never
                # crosses the printed value (a real collision seen in preview).
                label_end_x = max(label_end_x, hx)
            svg.append(f'<text x="{label_end_x + 6:.1f}" y="{yc:.1f}" class="pmb-c-val" '
                       f'dominant-baseline="middle">{esc(fmt_val(v["mean"]))}</text>')
        svg.append("</svg>")
        return "\n".join(svg)

    score_svg = panel("Score", lambda r: r["overall"], lambda v: f"{v:.3f}",
                       lambda t: f"{t:g}", 1.0, value_cap=1.0)
    cost_svg = panel("Cost", lambda r: r["cost"], fmt_cost,
                      lambda t: fmt_cost(t), 1.0)
    dur_svg = panel("Duration", lambda r: r["duration"], fmt_duration,
                     fmt_tick_duration, 60.0)

    tools_present = sorted({r["tool"] for r in recs}, key=lambda t: 0 if t == "modus" else 1)
    legend = " &nbsp;&nbsp; ".join(
        f'<span class="pmb-c-swatch" style="background:{TOOL_COLORS.get(t, TOOL_COLOR_FALLBACK)}"></span> {esc(t)}'
        for t in tools_present
    )

    return f"""
<style>
.pmb-chart-group {{ background:#fcfcfb; border:1px solid rgba(11,11,11,0.10); border-radius:12px;
  padding:16px 20px 12px; margin:18px 0; }}
.pmb-chart-legend {{ font-size:12px; color:#52514e; margin-bottom:6px; }}
.pmb-chart-panels {{ display:flex; flex-wrap:wrap; gap:16px; align-items:flex-start; }}
.pmb-chart-panel {{ flex:0 0 {PANEL_W}px; max-width:100%; }}
.pmb-chart-panel svg {{ display:block; width:100%; height:auto; }}
.pmb-c-title {{ font:600 12px system-ui,-apple-system,"Segoe UI",sans-serif; fill:#0b0b0b; }}
.pmb-c-label {{ font:12px system-ui,-apple-system,"Segoe UI",sans-serif; fill:#0b0b0b; }}
.pmb-c-val {{ font:11px system-ui,-apple-system,"Segoe UI",sans-serif; fill:#52514e; font-variant-numeric:tabular-nums; }}
.pmb-c-tick {{ font:10px system-ui,-apple-system,"Segoe UI",sans-serif; fill:#898781; }}
.pmb-c-grid {{ stroke:#e1e0d9; stroke-width:1; }}
.pmb-c-axis {{ stroke:#c3c2b7; stroke-width:1; }}
.pmb-c-whisker {{ stroke:#898781; stroke-width:1.25; }}
.pmb-c-swatch {{ display:inline-block; width:10px; height:10px; border-radius:2px; margin-right:4px; vertical-align:middle; }}
.pmb-chart-panels path:hover {{ opacity:0.85; }}
</style>
<div class="pmb-chart-group">
<div class="pmb-chart-legend">`{esc(dataset)}` &mdash; {legend}</div>
<div class="pmb-chart-panels">
<div class="pmb-chart-panel">{score_svg}</div>
<div class="pmb-chart-panel">{cost_svg}</div>
<div class="pmb-chart-panel">{dur_svg}</div>
</div>
</div>
"""


def render(records, results_dir, failed, excluded_datasets=(),
           hide_individual_runs=False):
    groups = defaultdict(list)
    for r in records:
        groups[group_key(r)].append(r)

    failed_by_key = defaultdict(int)
    for e in failed:
        failed_by_key[failed_key(e)] += e["count"]
    unmatched_failed_keys = set(failed_by_key)

    rows = []
    for key, recs in groups.items():
        dataset, tool, harness, model = key
        overall_stats = stats([r["overall"] for r in recs])
        cost_stats = stats([r["cost_usd"] for r in recs])
        duration_stats = stats([r["duration_s"] for r in recs])
        areas = defaultdict(list)
        for r in recs:
            for area, val in r["by_pmx_area"].items():
                areas[area].append(val)
        area_stats = {a: stats(v) for a, v in areas.items()}
        unmatched_failed_keys.discard(key)
        rows.append({
            "dataset": dataset, "tool": tool, "harness": harness, "model": model,
            "overall": overall_stats, "cost": cost_stats, "duration": duration_stats,
            "areas": area_stats, "n_runs": len(recs),
            "n_failed": failed_by_key.get(key, 0),
        })

    # Configs with only failed attempts (never a single successful run) still
    # belong on the board -- otherwise a 3/3 failure streak is invisible.
    for fk in unmatched_failed_keys:
        dataset, tool, harness, model = fk
        rows.append({
            "dataset": dataset, "tool": tool, "harness": harness, "model": model,
            "overall": stats([]), "cost": stats([]), "duration": stats([]), "areas": {}, "n_runs": 0,
            "n_failed": failed_by_key[fk],
        })

    rows.sort(key=lambda x: (x["overall"]["mean"] is None, -(x["overall"]["mean"] or 0)))

    area_names = sorted({a for row in rows for a in row["areas"]})

    lines = []
    lines.append("---")
    lines.append('title: "PMbench Leaderboard"')
    lines.append("sidebar: false")
    lines.append("---")
    lines.append("")
    lines.append(
        "Aggregated results from `tools/pharmbench`. Each row is one "
        "(scenario, tool, harness, model) configuration; repeated attempts "
        "of the identical configuration are grouped together, with mean/SD "
        "showing the spread across attempts rather than a single run "
        "standing in for the whole configuration. Tool/pharmbench git "
        "revision is intentionally not part of the grouping -- both are "
        "whole-monorepo HEAD SHAs, so they change on any commit anywhere in "
        "the repo, not just when the tool itself changes; see the linked "
        "run in \"Individual runs\" for a given attempt's exact revision."
    )
    if excluded_datasets:
        lines.append("")
        lines.append(
            f"**Excluded from this render:** `{'`, `'.join(sorted(excluded_datasets))}`. "
            "Still recorded in `tools/pharmbench/results/`, just left off this "
            "page for now -- regenerate without `--exclude-dataset` to bring "
            "it back."
        )
    lines.append("")
    lines.append(
        "**Failed** counts known attempts that never produced a submission "
        "(see \"Known failed attempts\" below). **Cost** is per-run API spend "
        "computed by the wrapper script from the harness's own accounting -- "
        "exact for `claude` (its own reported total) and `pi` (summed via "
        "OpenRouter's per-generation cost, so it stays correct even when "
        "runs overlap in time); unavailable for harnesses like `codex` that "
        "expose neither a total nor a per-request id to look one up, and for "
        "runs recorded before this was tracked. **Duration** is wall-clock "
        "time timed by the wrapper script itself (harness-agnostic, no "
        "concurrency caveats)."
    )
    lines.append("")
    lines.append(
        f"Generated from `{len(records)}` recorded run(s) across "
        f"`{len(rows)}` configuration(s). Regenerate with "
        "`python3 tools/pharmbench/generate_leaderboard.py` after adding new "
        "results to `tools/pharmbench/results/`."
    )
    lines.append("")

    datasets_in_order = []
    for row in rows:
        if row["dataset"] not in datasets_in_order:
            datasets_in_order.append(row["dataset"])
    for dataset in datasets_in_order:
        chart = render_config_charts(dataset, [r for r in rows if r["dataset"] == dataset])
        if chart:
            lines.append(chart)
    lines.append("")

    header = ["Scenario", "Tool", "Harness", "Model", "N", "Failed", "Overall (mean±sd)", "Min–Max",
              "Cost (mean±sd)", "Duration (mean)"] + \
        [a.replace("-", " ").title() for a in area_names]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("|" + "|".join(["---"] * len(header)) + "|")
    for row in rows:
        o = row["overall"]
        sd_str = f" ±{o['sd']:.3f}" if o["sd"] is not None else ""
        overall_str = f"**{fmt(o['mean'])}**{sd_str}" if o["mean"] is not None else "—"
        minmax_str = f"{fmt(o['min'])}–{fmt(o['max'])}" if row["n_runs"] > 1 else "—"
        c = row["cost"]
        cost_sd_str = f" ±{c['sd']:.2f}" if c["sd"] is not None else ""
        cost_str = f"{fmt_cost(c['mean'])}{cost_sd_str}"
        duration_str = fmt_duration(row["duration"]["mean"])
        cells = [
            f"`{row['dataset']}`",
            row["tool"],
            row["harness"],
            f"`{row['model']}`",
            str(row["n_runs"]),
            str(row["n_failed"]) if row["n_failed"] else "—",
            overall_str,
            minmax_str,
            cost_str,
            duration_str,
        ]
        for a in area_names:
            st = row["areas"].get(a, {"mean": None})
            cells.append(fmt(st["mean"]))
        lines.append("| " + " | ".join(cells) + " |")

    if failed:
        lines.append("")
        lines.append("## Known failed attempts")
        lines.append("")
        lines.append(
            "Runs that never produced a `submission.yaml` -- `score.R` has "
            "nothing to score without one, so these don't appear as their "
            "own folder in `results/`. Manually curated in "
            "`results/failed_runs.yaml`; `confidence: approximate` entries "
            "are carried over from an earlier session's notes with no "
            "surviving log to re-verify against."
        )
        lines.append("")
        failed_header = ["Date", "Scenario", "Tool", "Harness", "Model", "Count", "Confidence", "Failure mode"]
        lines.append("| " + " | ".join(failed_header) + " |")
        lines.append("|" + "|".join(["---"] * len(failed_header)) + "|")
        for e in sorted(failed, key=lambda x: x.get("date", ""), reverse=True):
            mode = " ".join(str(e.get("failure_mode", "")).split())
            lines.append("| " + " | ".join([
                e.get("date", "—"), f"`{e['dataset']}`", e["tool"], e["harness"],
                f"`{e['model']}`", str(e["count"]), e.get("confidence", "—"), mode,
            ]) + " |")

    # The per-run table links each run/slide at the results/ tree on the
    # `main` branch. Those files currently live only on `dev`, so the links
    # 404 on the published site -- withhold the whole section (opt-in, same
    # shape as --exclude-dataset) until the branch that hosts them is the one
    # the links point at. Every run stays recorded in results/ either way.
    if hide_individual_runs:
        lines.append("")
        lines.append(
            "*The per-run drill-down table is withheld from this render for "
            "now. Every run is still recorded in "
            "[`tools/pharmbench/results/`]"
            "(https://github.com/AIML-SIG/Agentic-workflows/tree/main/tools/pharmbench/results); "
            "regenerate without `--no-individual-runs` to list them.*"
        )
        return "\n".join(lines) + "\n"

    lines.append("")
    lines.append("## Individual runs")
    lines.append("")
    lines.append(
        "Raw records live in [`tools/pharmbench/results/`]"
        "(https://github.com/AIML-SIG/Agentic-workflows/tree/main/tools/pharmbench/results) "
        "-- one folder per run (`scorecard.yaml` + `submission.yaml` written by "
        "`score.R --record`, plus a `slide.html` rendered by this script). No "
        "raw agent log is archived (see `score.R`), so a slide's score "
        "breakdown and trap ledger are complete but it has no wall-clock/cost "
        "timeline."
    )
    lines.append("")
    run_header = ["Timestamp", "Scenario", "Tool", "Harness", "Model", "Overall", "Cost", "Duration", "Run"]
    lines.append("| " + " | ".join(run_header) + " |")
    lines.append("|" + "|".join(["---"] * len(run_header)) + "|")
    tree_url = "https://github.com/AIML-SIG/Agentic-workflows/tree/main/tools/pharmbench/results"
    blob_url = "https://github.com/AIML-SIG/Agentic-workflows/blob/main/tools/pharmbench/results"
    for r in sorted(records, key=lambda x: x["run_utc"], reverse=True):
        run_link = f"[`{r['run_dir']}`]({tree_url}/{r['run_dir']})"
        if r["slide"]:
            run_link += f" ([slide]({blob_url}/{r['run_dir']}/{r['slide']}))"
        run_header_cells = [
            r["run_utc"] or "—", f"`{r['dataset']}`", r["tool"], r["harness"],
            f"`{r['model']}`", fmt(r["overall"]), fmt_cost(r["cost_usd"]),
            fmt_duration(r["duration_s"]), run_link,
        ]
        lines.append("| " + " | ".join(run_header_cells) + " |")

    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default=str(SCRIPT_DIR / "results"))
    ap.add_argument("--out", default=str(REPO_ROOT / "docs" / "leaderboard.qmd"))
    ap.add_argument("--exclude-dataset", action="append", default=[],
                     help="Scenario dataset to leave off this render (repeatable). "
                          "Excluded runs stay recorded in results/, just not shown.")
    ap.add_argument("--no-individual-runs", action="store_true",
                     help="Withhold the per-run 'Individual runs' table (its "
                          "links point at results/ on `main`, which 404 while "
                          "those files live only on `dev`). Runs stay recorded "
                          "in results/, just not listed on the page.")
    args = ap.parse_args()

    results_dir = Path(args.results)
    results_dir.mkdir(parents=True, exist_ok=True)
    records = load_records(results_dir)
    failed = load_failed(results_dir)
    if args.exclude_dataset:
        excluded = set(args.exclude_dataset)
        records = [r for r in records if r["dataset"] not in excluded]
        failed = [e for e in failed if e["dataset"] not in excluded]

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render(records, results_dir, failed, args.exclude_dataset,
                               args.no_individual_runs))
    print(f"Wrote {out_path} from {len(records)} recorded run(s) "
          f"({sum(e['count'] for e in failed)} known failed attempt(s)) in {results_dir}")


if __name__ == "__main__":
    main()
