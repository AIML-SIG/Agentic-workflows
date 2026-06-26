#!/usr/bin/env Rscript
# PMbench scorer (scenario-agnostic).
#   Rscript score.R --truth scenarios/<id>/evals/truth.yaml path/to/submission.yaml
# Loads truth and the submission, scores each item in [0,1], and prints + writes
# scorecard.yaml next to the submission.
#
# Per-item scoring:
#   numeric     : relErr = |sub - exp| / |exp|; score = max(0, 1 - relErr / tol)
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
i <- 1
while (i <= length(argv)) {
  if (argv[[i]] == "--truth") {
    truth_path <- argv[[i + 1]]
    i <- i + 2
  } else {
    sub_path <- argv[[i]]
    i <- i + 1
  }
}
if (is.null(sub_path)) {
  stop("usage: Rscript score.R [--truth path/to/truth.yaml] path/to/submission.yaml")
}

# default truth: alongside this script if --truth not given (back-compat)
if (is.null(truth_path)) {
  this_file <- sub("^--file=", "",
                   grep("^--file=", commandArgs(FALSE), value = TRUE))
  script_dir <- if (length(this_file)) dirname(normalizePath(this_file)) else "."
  truth_path <- file.path(script_dir, "truth.yaml")
}
if (!file.exists(truth_path)) {
  stop(sprintf("truth file not found: %s (pass it with --truth)", truth_path))
}

truth <- yaml::read_yaml(truth_path)
sub   <- yaml::read_yaml(sub_path)
answers <- sub$answers

## ---- per-scorer helpers ------------------------------------------------
score_numeric <- function(submitted, expected, tol) {
  if (is.null(submitted)) return(0)
  # guard expected == 0: relative error is undefined, so treat tol as absolute.
  relErr <- if (expected == 0) abs(submitted) else abs(submitted - expected) / abs(expected)
  max(0, 1 - relErr / tol)
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
scorecard <- list(
  dataset = truth$meta$dataset,
  provenance = sub$provenance,
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
cat(sprintf("tool: %s @ %s   model: %s   run: %s\n",
            sub$provenance$tool, sub$provenance$tool_sha,
            sub$provenance$model, sub$provenance$run_utc))
sel <- sub$provenance$analysis_steps
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
