#!/usr/bin/env python3
"""Regenerate the leaderboard page from tools/pharmbench/results/<run>/.

Reads every recorded run (a `results/<slug>/scorecard.yaml`, written by
`score.R --record`, alongside its `submission.yaml`), groups by the
configuration that actually matters for comparability -- scenario,
pharmbench revision, tool, tool revision, harness, and model -- and computes
n/mean/sd/min/max of the overall score (and each pmx_area) within each group.
Repeated attempts of the identical configuration land in the same group,
which is where the variance comes from; anything that changed (a scorer fix,
a new task-library revision, a different model) gets its own group rather
than being silently averaged together.

Also (re)renders each run's drill-down slide via `visualize_results.py`, from
its scorecard + submission + the scenario's truth.yaml (no raw agent log --
see `score.R`'s record block for why those aren't archived), and links it
from the "Individual runs" table.

Output is a static Quarto page (docs/leaderboard.qmd) -- plain markdown, no
live code execution required to render it, since this repo's devcontainer
doesn't set up Quarto's R/Python execution engines.

Usage:
  python3 generate_leaderboard.py [--results DIR] [--out docs/leaderboard.qmd]
"""
import argparse
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


def truth_path_for(dataset):
    """`pmb-<scenario-id>` -> scenarios/<scenario-id>/evals/truth.yaml."""
    scenario_id = dataset[len("pmb-"):] if dataset.startswith("pmb-") else dataset
    path = SCRIPT_DIR / "scenarios" / scenario_id / "evals" / "truth.yaml"
    return path if path.exists() else None


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
            "model": prov.get("model", "unknown"),
            "run_utc": prov.get("run_utc", ""),
            "overall": sc.get("overall"),
            "by_pmx_area": sc.get("by_pmx_area", {}) or {},
        })
    return records


def group_key(r):
    return (r["dataset"], r["pharmbench_sha"], r["tool"], r["tool_sha"], r["harness"], r["model"])


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


def render(records, results_dir):
    groups = defaultdict(list)
    for r in records:
        groups[group_key(r)].append(r)

    rows = []
    for key, recs in groups.items():
        dataset, pharmbench_sha, tool, tool_sha, harness, model = key
        overall_stats = stats([r["overall"] for r in recs])
        areas = defaultdict(list)
        for r in recs:
            for area, val in r["by_pmx_area"].items():
                areas[area].append(val)
        area_stats = {a: stats(v) for a, v in areas.items()}
        rows.append({
            "dataset": dataset, "tool": tool, "harness": harness, "model": model,
            "tool_sha": tool_sha, "pharmbench_sha": pharmbench_sha,
            "overall": overall_stats, "areas": area_stats, "n_runs": len(recs),
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
        "(scenario, pharmbench revision, tool, tool revision, harness, model) "
        "configuration; repeated attempts of the identical configuration are "
        "grouped together, with mean/SD showing the spread across attempts "
        "rather than a single run standing in for the whole configuration. "
        "A changed scorer/truth revision, task-library revision, or model "
        "gets its own row rather than being silently averaged with older "
        "results."
    )
    lines.append("")
    lines.append(
        f"Generated from `{len(records)}` recorded run(s) across "
        f"`{len(rows)}` configuration(s). Regenerate with "
        "`python3 tools/pharmbench/generate_leaderboard.py` after adding new "
        "results to `tools/pharmbench/results/`."
    )
    lines.append("")

    header = ["Scenario", "Tool", "Harness", "Model", "N", "Overall (mean±sd)", "Min–Max"] + \
        [a.replace("-", " ").title() for a in area_names]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("|" + "|".join(["---"] * len(header)) + "|")
    for row in rows:
        o = row["overall"]
        sd_str = f" ±{o['sd']:.3f}" if o["sd"] is not None else ""
        overall_str = f"**{fmt(o['mean'])}**{sd_str}"
        minmax_str = f"{fmt(o['min'])}–{fmt(o['max'])}" if row["n_runs"] > 1 else "—"
        cells = [
            f"`{row['dataset']}`",
            row["tool"],
            row["harness"],
            f"`{row['model']}`",
            str(row["n_runs"]),
            overall_str,
            minmax_str,
        ]
        for a in area_names:
            st = row["areas"].get(a, {"mean": None})
            cells.append(fmt(st["mean"]))
        lines.append("| " + " | ".join(cells) + " |")

    lines.append("")
    lines.append("## Configuration detail")
    lines.append("")
    lines.append(
        "`tool_sha` / `pharmbench_sha` are the git revisions of the workflow "
        "and of pharmbench itself at run time (short form). Both live in the "
        "same monorepo today, so they coincide unless a workflow becomes a "
        "separate repo in the future."
    )
    lines.append("")
    detail_header = ["Scenario", "Tool", "tool_sha", "pharmbench_sha", "Harness", "Model", "N"]
    lines.append("| " + " | ".join(detail_header) + " |")
    lines.append("|" + "|".join(["---"] * len(detail_header)) + "|")
    for row in rows:
        lines.append("| " + " | ".join([
            f"`{row['dataset']}`", row["tool"], f"`{row['tool_sha']}`",
            f"`{row['pharmbench_sha']}`", row["harness"], f"`{row['model']}`",
            str(row["n_runs"]),
        ]) + " |")

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
    run_header = ["Timestamp", "Scenario", "Tool", "Harness", "Model", "Overall", "Run"]
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
            f"`{r['model']}`", fmt(r["overall"]), run_link,
        ]
        lines.append("| " + " | ".join(run_header_cells) + " |")

    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default=str(SCRIPT_DIR / "results"))
    ap.add_argument("--out", default=str(REPO_ROOT / "docs" / "leaderboard.qmd"))
    args = ap.parse_args()

    results_dir = Path(args.results)
    results_dir.mkdir(parents=True, exist_ok=True)
    records = load_records(results_dir)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render(records, results_dir))
    print(f"Wrote {out_path} from {len(records)} recorded run(s) in {results_dir}")


if __name__ == "__main__":
    main()
