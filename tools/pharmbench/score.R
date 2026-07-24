#!/usr/bin/env Rscript
# PMbench scorer (scenario-agnostic).
#   Rscript score.R --truth scenarios/<id>/evals/truth.yaml path/to/submission.yaml
# Loads truth and the submission, scores each item in [0,1], and prints + writes
# scorecard.yaml next to the submission.
#
# Per-item scoring:
#   numeric     : relErr = |sub - exp| / |exp|; score = exp(-relErr / tol)
#                 (1 at zero error, ~0.37 at exactly 1x tol, decays smoothly
#                 toward 0 beyond -- a reported-but-off value never hits a hard
#                 floor the way an unanswered item does; see `missing` below)
#   categorical : 1 if sub == exp else 0
#   set         : precision/recall of sub vs expected, F1 = 2PR/(P+R).
#                 both empty -> 1; sub empty vs nonempty expected -> 0.
#                 decoys are absent from expected, so including one lowers precision.
#   missing     : an unanswered item (key absent or null) scores 0, any scorer.
#                 This is how under-scoping self-penalizes -- a task family the
#                 build stage never selected leaves its items unanswered.
# Aggregation: weighted mean within each `pmx_area` (the pharmacometric knowledge
# area an item tests) and overall. provenance.analysis_steps lists the steps the
# workflow ran, in its own vocabulary; PMbench echoes them verbatim and never
# parses or scores them.

suppressPackageStartupMessages(library(yaml))

## ---- argument parsing --------------------------------------------------
argv <- commandArgs(trailingOnly = TRUE)
truth_path <- NULL
sub_path   <- NULL
record     <- FALSE
i <- 1
while (i <= length(argv)) {
  if (argv[[i]] == "--truth") {
    truth_path <- argv[[i + 1]]
    i <- i + 2
  } else if (argv[[i]] == "--record") {
    record <- TRUE
    i <- i + 1
  } else {
    sub_path <- argv[[i]]
    i <- i + 1
  }
}
if (is.null(sub_path)) {
  stop("usage: Rscript score.R [--truth path/to/truth.yaml] [--record] path/to/submission.yaml")
}

this_file <- sub("^--file=", "",
                 grep("^--file=", commandArgs(FALSE), value = TRUE))
script_dir <- if (length(this_file)) dirname(normalizePath(this_file)) else "."

# default truth: alongside this script if --truth not given (back-compat)
if (is.null(truth_path)) {
  truth_path <- file.path(script_dir, "truth.yaml")
}
if (!file.exists(truth_path)) {
  stop(sprintf("truth file not found: %s (pass it with --truth)", truth_path))
}

# pharmbench's own git SHA -- distinguishes scorer/truth revisions under the
# same scenario_id (e.g. an alias-list or trap fix), independent of the
# scenario's own "-vN" versioning.
pharmbench_sha <- tryCatch({
  s <- suppressWarnings(system2("git", c("-C", shQuote(script_dir), "rev-parse", "--short=12", "HEAD"),
                                 stdout = TRUE, stderr = FALSE))
  if (length(s) == 1 && nzchar(s)) s else NA_character_
}, error = function(e) NA_character_)

truth <- yaml::read_yaml(truth_path)
sub   <- yaml::read_yaml(sub_path)
answers <- sub$answers

# run_meta.yaml sidecar: harness/tool_sha/agent_cmd/cost_usd/duration_s as
# written by the wrapper script that actually invoked the agent (baseline.sh /
# modus/run.sh)
# -- these are facts the orchestrator knows authoritatively, not something to
# trust the agent's own provenance block to self-report correctly.
# Conventionally sits one level up from submission.yaml (i.e. next to the
# submission/ directory);
# absent for older runs or hand-authored submissions, which is fine.
run_meta <- NULL
for (candidate in c(file.path(dirname(dirname(normalizePath(sub_path))), "run_meta.yaml"),
                     file.path(dirname(normalizePath(sub_path)), "run_meta.yaml"))) {
  if (file.exists(candidate)) { run_meta <- yaml::read_yaml(candidate); break }
}

## ---- per-scorer helpers ------------------------------------------------
score_numeric <- function(submitted, expected, tol) {
  if (is.null(submitted)) return(0)
  # guard expected == 0: relative error is undefined, so treat tol as absolute.
  relErr <- if (expected == 0) abs(submitted) else abs(submitted - expected) / abs(expected)
  exp(-relErr / tol)
}

score_categorical <- function(submitted, expected) {
  if (is.null(submitted)) return(0)
  as.numeric(submitted == expected)
}

score_set <- function(submitted, expected) {
  submitted <- as.character(submitted)
  expected  <- as.character(expected)
  if (length(expected) == 0 && length(submitted) == 0) return(1)
  if (length(submitted) == 0) return(0)               # nonempty expected, empty sub
  if (length(expected) == 0)  return(0)               # spurious picks against empty truth
  tp <- length(intersect(submitted, expected))
  precision <- tp / length(submitted)
  recall    <- tp / length(expected)
  if (precision + recall == 0) return(0)
  2 * precision * recall / (precision + recall)
}

# Name matching for map scorers: normalize and resolve aliases to a canonical
# name, so a submission may report CL/cl or Vc/vc/v1 without penalty. The
# workflow supplies the keys; truth holds the canonical set and any aliases.
norm_name <- function(x) tolower(trimws(as.character(x)))

# build a canonicalizer from truth's `aliases: {Canonical: [v1, v2]}` block:
# any accepted variant (normalized) maps to the canonical (normalized) name.
make_canon <- function(aliases) {
  lut <- list()
  if (!is.null(aliases)) {
    for (cn in names(aliases)) {
      for (a in c(cn, unlist(aliases[[cn]]))) lut[[norm_name(a)]] <- norm_name(cn)
    }
  }
  function(x) { nx <- norm_name(x); if (!is.null(lut[[nx]])) lut[[nx]] else nx }
}

# map scorer: expected and submitted are name->value maps. Score over the UNION
# of names -- a matched name scores numeric (tol); a name in expected but not
# submitted, or submitted but not expected (a spurious/decoy entry), scores 0.
# This is the set scorer's precision/recall behavior, valued by numeric error.
# Both empty -> 1.
score_map <- function(submitted, expected, tol, aliases = NULL) {
  canon <- make_canon(aliases)
  exp_v <- list(); for (n in names(expected))  exp_v[[canon(n)]] <- expected[[n]]
  sub_v <- list()
  if (!is.null(submitted)) for (n in names(submitted)) sub_v[[canon(n)]] <- submitted[[n]]
  keys <- union(names(exp_v), names(sub_v))
  if (length(keys) == 0) return(1)
  mean(vapply(keys, function(k) {
    if (is.null(exp_v[[k]])) return(0)                       # spurious / decoy
    score_numeric(sub_v[[k]], exp_v[[k]], tol)               # missing sub -> 0
  }, numeric(1)))
}

# nested map scorer: param -> covariate -> value (e.g. cov_effects). Flatten to
# "param::cov" keys, canonicalizing both levels, then score like score_map.
# The workflow must get the parameter, the covariate, AND the magnitude right;
# an effect on the wrong parameter or a decoy covariate is a spurious key (0).
score_map_nested <- function(submitted, expected, tol, aliases = NULL) {
  canon <- make_canon(aliases)
  flat <- function(m) {
    out <- list()
    if (is.null(m)) return(out)
    for (p in names(m)) {
      inner <- m[[p]]
      if (!is.null(inner) && !is.null(names(inner)))
        for (cv in names(inner)) out[[paste0(canon(p), "::", canon(cv))]] <- inner[[cv]]
    }
    out
  }
  exp_v <- flat(expected); sub_v <- flat(submitted)
  keys <- union(names(exp_v), names(sub_v))
  if (length(keys) == 0) return(1)
  mean(vapply(keys, function(k) {
    if (is.null(exp_v[[k]])) return(0)
    score_numeric(sub_v[[k]], exp_v[[k]], tol)
  }, numeric(1)))
}

# collect the leaf names a map/nested-map submission reports, for trap watching.
submitted_names <- function(sub_ans, nested) {
  if (is.null(sub_ans)) return(character(0))
  if (!nested) return(names(sub_ans))
  unlist(lapply(sub_ans, function(inner) if (!is.null(names(inner))) names(inner)))
}

## ---- score each item ---------------------------------------------------
item_scores <- list()
traps_note  <- character(0)
unanswered  <- character(0)

for (it in truth$items) {
  id  <- it$id
  sc  <- it$scorer
  sub_ans <- answers[[id]]
  if (is.null(sub_ans)) unanswered <- c(unanswered, id)
  s <- switch(sc,
    numeric     = score_numeric(sub_ans, it$expected, it$tol),
    categorical = score_categorical(sub_ans, it$expected),
    set         = score_set(sub_ans, it$expected),
    map         = score_map(sub_ans, it$expected, it$tol, it$aliases),
    map_nested  = score_map_nested(sub_ans, it$expected, it$tol, it$aliases),
    stop(sprintf("unknown scorer '%s' for item '%s'", sc, id))
  )
  item_scores[[id]] <- list(
    score = round(s, 4),
    scorer = sc,
    answered = !is.null(sub_ans),
    pmx_area = it$pmx_area,
    weight = it$weight
  )

  # trap watching: flag any decoy that appears in a submitted answer. For set
  # items the decoy is a submitted element; for map / nested-map items it is a
  # reported name (e.g. a covariate effect on a decoy covariate).
  if (!is.null(it$decoys) && !is.null(sub_ans)) {
    reported <- if (sc %in% c("map", "map_nested"))
      submitted_names(sub_ans, sc == "map_nested") else as.character(sub_ans)
    hit <- intersect(norm_name(reported), norm_name(it$decoys))
    if (length(hit)) {
      traps_note <- c(traps_note,
        sprintf("%s: decoy(s) included -> %s", id, paste(hit, collapse = ", ")))
    }
  }
}

## ---- weighted aggregation ----------------------------------------------
agg_by <- function(field) {
  keys <- unique(vapply(item_scores, function(x) x[[field]], character(1)))
  out <- list()
  for (k in keys) {
    sel <- Filter(function(x) x[[field]] == k, item_scores)
    w   <- vapply(sel, function(x) x$weight, numeric(1))
    sc  <- vapply(sel, function(x) x$score,  numeric(1))
    out[[k]] <- round(sum(w * sc) / sum(w), 4)
  }
  out
}

all_w  <- vapply(item_scores, function(x) x$weight, numeric(1))
all_sc <- vapply(item_scores, function(x) x$score,  numeric(1))
overall <- round(sum(all_w * all_sc) / sum(all_w), 4)

by_pmx_area <- agg_by("pmx_area")

if (length(traps_note) == 0) {
  traps_note <- "none detected"
}
if (length(unanswered) == 0) {
  unanswered_note <- "none"
} else {
  unanswered_note <- unanswered
}

## ---- assemble scorecard ------------------------------------------------
# Merge run_meta over the agent's self-reported provenance: harness and
# tool_sha are facts the wrapper script knows authoritatively, so they take
# precedence over (or fill gaps in) what the agent wrote.
provenance <- sub$provenance
provenance$pharmbench_sha <- pharmbench_sha
if (!is.null(run_meta)) {
  if (!is.null(run_meta$harness))   provenance$harness   <- run_meta$harness
  if (!is.null(run_meta$tool_sha))  provenance$tool_sha   <- run_meta$tool_sha
  if (!is.null(run_meta$agent_cmd)) provenance$agent_cmd  <- run_meta$agent_cmd
  # model, when the wrapper script can pull it straight off AGENT_CMD's
  # --model flag, is likewise more trustworthy than the agent's own
  # self-report -- e.g. a GLM-5.2 run once reported "nlmixr2 (FOCEI)" (the
  # estimation method) as its "model", and an Opus run left it blank.
  if (!is.null(run_meta$model) && nzchar(run_meta$model)) provenance$model <- run_meta$model
  # cost_usd: computed by the wrapper script from the harness's own log
  # (claude's total_cost_usd, or OpenRouter's per-generation-id cost for pi)
  # after the run finishes -- absent for harnesses (e.g. codex) that expose
  # neither, rather than guessed.
  if (!is.null(run_meta$cost_usd) && nzchar(run_meta$cost_usd)) provenance$cost_usd <- run_meta$cost_usd
  # duration_s: wall-clock seconds for the whole run, timed by the wrapper
  # script itself (start of the single agent call for baseline.sh, start of
  # the whole iteration loop for modus/run.sh) -- harness-agnostic.
  if (!is.null(run_meta$duration_s) && nzchar(run_meta$duration_s)) provenance$duration_s <- run_meta$duration_s
}

scorecard <- list(
  dataset = truth$meta$dataset,
  provenance = provenance,
  items = lapply(item_scores, function(x)
    list(score = x$score, scorer = x$scorer, answered = x$answered,
         pmx_area = x$pmx_area, weight = x$weight)),
  by_pmx_area = by_pmx_area,
  overall = overall,
  unanswered_items = unanswered_note,
  traps_fallen_for = traps_note
)

## ---- print -------------------------------------------------------------
cat("===== PMbench scorecard =====\n")
cat("dataset:", scorecard$dataset, "\n")
cat(sprintf("tool: %s @ %s   harness: %s   model: %s   run: %s\n",
            provenance$tool, provenance$tool_sha,
            if (is.null(provenance$harness)) "unknown" else provenance$harness,
            provenance$model, provenance$run_utc))
cat("pharmbench_sha:", if (is.na(pharmbench_sha)) "unknown" else pharmbench_sha, "\n")
sel <- provenance$analysis_steps
if (!is.null(sel)) {
  cat("analysis_steps:", paste(unlist(sel), collapse = ", "), "\n")
}
cat("\n-- item scores --\n")
for (id in names(item_scores)) {
  x <- item_scores[[id]]
  flag <- if (!x$answered) "  (unanswered)" else ""
  cat(sprintf("  %-18s %.3f  [%s, %s]%s\n",
              id, x$score, x$scorer, x$pmx_area, flag))
}
cat("\n-- by pmx_area --\n")
for (k in names(by_pmx_area)) cat(sprintf("  %-20s %.3f\n", k, by_pmx_area[[k]]))
cat(sprintf("\noverall: %.3f\n", overall))
if (length(unanswered)) {
  cat("\nunanswered items (scored 0):", paste(unanswered, collapse = ", "), "\n")
}
cat("\ntraps fallen for:\n")
for (t in traps_note) cat("  -", t, "\n")

## ---- write -------------------------------------------------------------
out_path <- file.path(dirname(normalizePath(sub_path)), "scorecard.yaml")
yaml::write_yaml(scorecard, out_path)
cat("\nscorecard written to", out_path, "\n")

## ---- record (opt-in) ----------------------------------------------------
# Leaderboard entry: a slugged, timestamped run folder under results/, holding
# the scorecard and a copy of the submission (small, harness-agnostic -- raw
# agent logs are deliberately NOT archived here: sizes range from a few KB to
# hundreds of MB, and parsing them for drill-down would mean a bespoke
# extractor per harness's log format). Off by default -- ad hoc/dev/smoke-test
# scoring (e.g. the documented submission.example.yaml check) shouldn't
# silently create an entry; pass --record for a run meant to count.
if (record) {
  slug <- function(x) {
    if (is.null(x) || is.na(x) || !nzchar(x)) return("unknown")
    x <- tolower(as.character(x))
    x <- gsub("[^a-z0-9]+", "-", x)
    gsub("^-+|-+$", "", x)
  }
  run_ts <- provenance$run_utc
  ts_slug <- if (!is.null(run_ts) && nzchar(run_ts)) {
    gsub("[^0-9TZ]", "", run_ts)
  } else {
    format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  }
  run_id <- substr(paste0(as.hexmode(sample(16^6, 1))), 1, 6)

  results_dir <- file.path(script_dir, "results")
  run_slug <- sprintf("%s__%s__%s__%s__%s__%s",
                       slug(scorecard$dataset), slug(provenance$tool),
                       slug(provenance$harness), slug(provenance$model),
                       ts_slug, run_id)
  run_dir <- file.path(results_dir, run_slug)
  dir.create(run_dir, showWarnings = FALSE, recursive = TRUE)

  yaml::write_yaml(scorecard, file.path(run_dir, "scorecard.yaml"))
  file.copy(sub_path, file.path(run_dir, "submission.yaml"), overwrite = TRUE)
  cat("recorded to", run_dir, "\n")
  cat("  regenerate the leaderboard (also renders this run's drill-down slide):\n")
  cat("  python3 generate_leaderboard.py\n")
}
