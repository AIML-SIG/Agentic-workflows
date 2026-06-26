#!/usr/bin/env Rscript
# PMbench v0 synthetic dataset: generic IgG1 mAb, 2-compartment, linear CL, single IV infusion.
# Build-time only -- held out of the agent's working directory.
# Fixed seed -> reproducible. Output committed as ../scenario/pmb-mab-poppk-v0.csv.
# Simulation engine: mrgsolve.
#
# True model (the answer key in ../evals/truth.yaml is derived from these):
#   CL  = 0.20 L/day * (WT/70)^0.75 * exp(eta.CL)   IIV ~30% CV
#   Vc  = 3.0  L     * (WT/70)^1.00 * exp(eta.Vc)   IIV ~20% CV
#   Q   = 0.6  L/day
#   Vp  = 3.0  L
#   proportional residual error ~15%
# Reference weight 70 kg, so typical CL/Vc at 70 kg are exactly 0.20 and 3.0.
#
# Covariates:
#   WT   true power effect on CL (exp 0.75) and Vc (exp 1.0) -- the signal to find
#   ALB  correlated with WT (target Pearson r ~0.4), ZERO effect -- confounder trap
#   CRCL independent, ZERO effect -- small-molecule-habit trap (mAbs are catabolized)
#
# Injected data issues:
#   BLQ  true conc < LLOQ -> DV=0, BLQ=1  (predose zeros + genuine terminal-phase
#        censoring at the late samples; scored implicitly via numeric tolerance)
#   Outliers: subjects 5, 50, 95 at day-7 sample, DV * 10 (decimal slip)

suppressPackageStartupMessages({
  library(mrgsolve)
})

set.seed(1234)

# resolve output path relative to this script, so it runs from any cwd
args_all   <- commandArgs(FALSE)
this_file  <- sub("^--file=", "", grep("^--file=", args_all, value = TRUE))
script_dir <- if (length(this_file)) dirname(normalizePath(this_file)) else "."
out_csv    <- normalizePath(file.path(script_dir, "..", "scenario",
                                      "pmb-mab-poppk-v0.csv"), mustWork = FALSE)

## ---- true parameters ---------------------------------------------------
TVCL <- 0.20   # L/day at 70 kg
TVVc <- 3.0    # L     at 70 kg
TVQ  <- 0.6    # L/day
TVVp <- 3.0    # L
WT_REF    <- 70
EXP_CL_WT <- 0.75
EXP_VC_WT <- 1.0

# IIV as lognormal: omega = sqrt(log(1 + CV^2))
om_CL <- sqrt(log(1 + 0.30^2))
om_Vc <- sqrt(log(1 + 0.20^2))
PROP_ERR <- 0.15

LLOQ <- 0.1    # mg/L

## ---- design ------------------------------------------------------------
N_PER_DOSE <- 40
DOSES <- c(100, 300, 600)          # mg
N <- N_PER_DOSE * length(DOSES)    # 120 subjects
INF_DUR <- 1 / 24                  # 1-hour infusion, in days

# sample times in days: predose, end of infusion, then the listed days.
# The late tail (90/120/150) lets the low-exposure terminal phase decay below
# LLOQ, producing genuine terminal-phase BLQ (~6.6 half-lives at day 150).
SAMPLE_DAYS  <- c(0, 1, 3, 7, 14, 28, 42, 56, 70, 90, 120, 150)
SAMPLE_TIMES <- sort(unique(c(0, INF_DUR, SAMPLE_DAYS)))
# DAY label for each observation time (end-of-infusion shares DAY 0)
DAY_OF_TIME <- ifelse(SAMPLE_TIMES <= INF_DUR, 0, round(SAMPLE_TIMES))

## ---- subject-level covariates and random effects -----------------------
# Subjects 1-40 -> 100 mg, 41-80 -> 300 mg, 81-120 -> 600 mg.
# This puts the outlier subjects (5, 50, 95) one per dose group.
dose_vec <- rep(DOSES, each = N_PER_DOSE)

# Body weight: realistic adult spread, truncated to [50, 110] kg.
wt <- pmin(pmax(rnorm(N, mean = 78, sd = 14), 50), 110)

# Albumin correlated with weight (target r ~0.4), zero PK effect.
wt_z   <- (wt - mean(wt)) / sd(wt)
r_targ <- 0.4
alb_z  <- r_targ * wt_z + sqrt(1 - r_targ^2) * rnorm(N)
alb    <- 4.3 + 0.4 * alb_z                 # g/dL, ~3.5-5.0

# Creatinine clearance: independent of weight by construction, zero PK effect.
# Residualize a single N-draw against weight so the sample r(WT, CRCL) ~ 0 (the
# "independent" design intent), then rescale to the target mean/sd. Using exactly
# one rnorm(N) call keeps the downstream RNG stream (etas, residuals) unchanged.
crcl_e <- rnorm(N)
crcl_e <- residuals(lm(crcl_e ~ wt_z))      # remove any weight component
crcl_e <- crcl_e / sd(crcl_e)               # unit variance
crcl   <- pmin(pmax(100 + 25 * crcl_e, 40), 160)  # mL/min

eta_CL <- rnorm(N, 0, om_CL)
eta_Vc <- rnorm(N, 0, om_Vc)

CLi <- TVCL * (wt / WT_REF)^EXP_CL_WT * exp(eta_CL)
Vci <- TVVc * (wt / WT_REF)^EXP_VC_WT * exp(eta_Vc)
Qi  <- rep(TVQ, N)
Vpi <- rep(TVVp, N)

## ---- structural model (mrgsolve) ---------------------------------------
# 2-compartment, IV infusion into CENT. Parameters supplied per-subject in idata.
code <- '
$PARAM CL = 0.2, VC = 3, Q = 0.6, VP = 3
$CMT CENT PERI
$ODE
double k10 = CL / VC;
double k12 = Q / VC;
double k21 = Q / VP;
dxdt_CENT = -(k10 + k12) * CENT + k21 * PERI;
dxdt_PERI =  k12 * CENT - k21 * PERI;
$TABLE
double CP = CENT / VC;
$CAPTURE CP
'
mod <- mcode("pmb_mab_2cmt", code)

## ---- build event + idata, simulate all subjects ------------------------
# one infusion event per subject; rate = dose / infusion duration (mg/day)
dosing <- data.frame(
  ID   = seq_len(N),
  time = 0,
  amt  = dose_vec,
  rate = dose_vec / INF_DUR,
  cmt  = 1,
  evid = 1
)
idata <- data.frame(ID = seq_len(N), CL = CLi, VC = Vci, Q = Qi, VP = Vpi)

sim <- mod |>
  data_set(dosing) |>
  idata_set(idata) |>
  obsonly() |>
  mrgsim(tgrid = SAMPLE_TIMES, recsort = 3) |>
  as.data.frame()

# map each observation time back to its DAY label
sim$DAY <- DAY_OF_TIME[match(round(sim$time, 6), round(SAMPLE_TIMES, 6))]
names(sim)[names(sim) == "time"] <- "TIME"

## ---- residual error, covariates, BLQ ----------------------------------
sim$CP <- pmax(sim$CP, 0)
ipred  <- sim$CP
dv <- ipred * (1 + rnorm(nrow(sim), 0, PROP_ERR))   # proportional residual error
dv[dv < 0] <- 0
sim$DV <- dv

# attach subject covariates and dose
sim$DOSE <- dose_vec[sim$ID]
sim$WT   <- round(wt[sim$ID], 1)
sim$ALB  <- round(alb[sim$ID], 2)
sim$CRCL <- round(crcl[sim$ID], 1)

# BLQ: true (IPRED) concentration below LLOQ -> reported as DV = 0, BLQ = 1.
sim$BLQ <- as.integer(ipred < LLOQ)
sim$DV  <- ifelse(sim$BLQ == 1, 0, signif(sim$DV, 4))

## ---- assemble final long table with a dosing row per subject ----------
obs_rows <- data.frame(
  ID   = sim$ID,  DAY = sim$DAY, TIME = sim$TIME, DV = sim$DV, AMT = 0,
  DOSE = sim$DOSE, WT = sim$WT,  ALB = sim$ALB,   CRCL = sim$CRCL, BLQ = sim$BLQ
)
dose_rows <- data.frame(
  ID   = seq_len(N), DAY = 0, TIME = 0, DV = NA_real_, AMT = dose_vec,
  DOSE = dose_vec, WT = round(wt, 1), ALB = round(alb, 2),
  CRCL = round(crcl, 1), BLQ = 0L
)

dat <- rbind(dose_rows, obs_rows)
# order: subject, then dosing row first (AMT>0) then observations by time
dat <- dat[order(dat$ID, dat$TIME, -dat$AMT), ]
# stable row id = sequential integer over the final row order. (ID-DAY is NOT
# unique -- the dosing, predose, and end-of-infusion rows all share DAY 0 -- so a
# plain row counter is the unambiguous record key, as in a NONMEM dataset.)
dat$ROWID <- seq_len(nrow(dat))

## ---- inject data-entry outliers ---------------------------------------
# subjects 5, 50, 95 at their day-7 observation: DV * 10 (decimal slip).
# Identify the rows by their semantic key (subject + day + observation), then
# read back the ROWIDs that land there for the answer key.
is_out <- with(dat, ID %in% c(5, 50, 95) & AMT == 0 & DAY == 7)
dat$DV[is_out] <- signif(dat$DV[is_out] * 10, 4)
outlier_ids <- dat$ROWID[is_out]

## ---- write -------------------------------------------------------------
write.csv(dat, out_csv, row.names = FALSE, na = ".")

## ---- sanity checks printed to console ---------------------------------
# terminal half-life from the true typical (70 kg) parameters
k10 <- TVCL / TVVc; k12 <- TVQ / TVVc; k21 <- TVQ / TVVp
s <- k10 + k12 + k21; p <- k10 * k21
beta <- 0.5 * (s - sqrt(s^2 - 4 * p))
thalf <- log(2) / beta

n_obs <- sum(dat$AMT == 0)
n_blq <- sum(dat$BLQ == 1 & dat$AMT == 0)

cat("PMbench v0 dataset written to", out_csv, "\n")
cat(sprintf("subjects: %d   observation records: %d   dosing records: %d\n",
            N, n_obs, sum(dat$AMT > 0)))
cat(sprintf("terminal half-life (typical, 70 kg): %.1f days (~%.1f weeks)\n",
            thalf, thalf / 7))
cat(sprintf("BLQ records: %d (%.1f%% of observations)\n",
            n_blq, 100 * n_blq / n_obs))
cat(sprintf("Pearson r(WT, ALB): %.2f\n", cor(wt, alb)))
cat(sprintf("Pearson r(WT, CRCL): %.2f\n", cor(wt, crcl)))
cat("corrupted outlier ROWIDs (subjects 5/50/95, day 7, DV x10):",
    paste(outlier_ids, collapse = ", "), "\n")
cat("  (copy these into truth.yaml `outlier_records`)\n")
cat("outlier rows present:", sum(is_out), "of 3\n")
