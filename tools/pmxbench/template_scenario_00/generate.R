#!/usr/bin/env Rscript
# Builds this scenario's data.csv from a fixed seed. Optionally draws EDA plots.
#
#   Rscript generate.R            # writes data.csv next to this script
#   Rscript generate.R --plots    # also writes figures/*.png (they mark the traps)
#
# Needs: install.packages("mrgsolve") and a C toolchain (mrgsolve compiles the ODEs).
#
# Every scenario's generate.R has the same three parts:
#   1. the TRUE MODEL, which truth.yaml is read off;
#   2. the TRAPS, each injected on purpose and listed in truth.yaml;
#   3. sanity checks printed to the console.
#
# Scenario 00: generic IgG1 mAb, 2-compartment, linear CL, single 1-h IV infusion.
#   CL = 0.20 L/day * (WT/70)^0.75 * exp(eta)   IIV 30% CV
#   Vc = 3.0  L     * (WT/70)^1.00 * exp(eta)   IIV 20% CV
#   Q  = 0.6 L/day,  Vp = 3.0 L,  proportional residual error 15%
# Traps: ALB correlated with WT (r ~0.4) but no effect; CRCL independent, no
# effect; BLQ at LLOQ 0.1 mg/L; DV x10 decimal slips at subjects 5/50/95, day 7.

suppressPackageStartupMessages(library(mrgsolve))
set.seed(1234)

args_all   <- commandArgs(FALSE)
this_file  <- sub("^--file=", "", grep("^--file=", args_all, value = TRUE))
script_dir <- if (length(this_file)) dirname(normalizePath(this_file)) else "."
out_csv    <- file.path(script_dir, "data.csv")
make_plots <- "--plots" %in% commandArgs(TRUE)

## ---- 1. true model -----------------------------------------------------
TVCL <- 0.20; TVVc <- 3.0; TVQ <- 0.6; TVVp <- 3.0   # at 70 kg
WT_REF <- 70; EXP_CL_WT <- 0.75; EXP_VC_WT <- 1.0
om_CL <- sqrt(log(1 + 0.30^2))                        # lognormal IIV from CV
om_Vc <- sqrt(log(1 + 0.20^2))
PROP_ERR <- 0.15
LLOQ <- 0.1                                           # mg/L

## ---- design ------------------------------------------------------------
N_PER_DOSE <- 40
DOSES <- c(100, 300, 600)                             # mg
N <- N_PER_DOSE * length(DOSES)
INF_DUR <- 1 / 24                                     # days
SAMPLE_DAYS  <- c(0, 1, 3, 7, 14, 28, 42, 56, 70, 90, 120, 150)
SAMPLE_TIMES <- sort(unique(c(0, INF_DUR, SAMPLE_DAYS)))
DAY_OF_TIME  <- ifelse(SAMPLE_TIMES <= INF_DUR, 0, round(SAMPLE_TIMES))

## ---- subjects, covariates, random effects ------------------------------
# The order of the rnorm() calls fixes the RNG stream; changing it changes the data.
dose_vec <- rep(DOSES, each = N_PER_DOSE)             # outlier subjects 5/50/95: one per dose
wt <- pmin(pmax(rnorm(N, mean = 78, sd = 14), 50), 110)

# TRAP: albumin tracks weight (r ~0.4) but has no PK effect.
wt_z  <- (wt - mean(wt)) / sd(wt)
alb_z <- 0.4 * wt_z + sqrt(1 - 0.4^2) * rnorm(N)
alb   <- 4.3 + 0.4 * alb_z                            # g/dL

# TRAP: creatinine clearance, residualized against weight so r(WT, CRCL) ~ 0, no effect.
crcl_e <- rnorm(N)
crcl_e <- residuals(lm(crcl_e ~ wt_z))
crcl_e <- crcl_e / sd(crcl_e)
crcl   <- pmin(pmax(100 + 25 * crcl_e, 40), 160)      # mL/min

eta_CL <- rnorm(N, 0, om_CL)
eta_Vc <- rnorm(N, 0, om_Vc)
CLi <- TVCL * (wt / WT_REF)^EXP_CL_WT * exp(eta_CL)
Vci <- TVVc * (wt / WT_REF)^EXP_VC_WT * exp(eta_Vc)

## ---- simulate ----------------------------------------------------------
mod <- mcode("pmb_mab_2cmt", '
$PARAM CL = 0.2, VC = 3, Q = 0.6, VP = 3
$CMT CENT PERI
$ODE
dxdt_CENT = -(CL/VC + Q/VC) * CENT + Q/VP * PERI;
dxdt_PERI =  Q/VC * CENT - Q/VP * PERI;
$TABLE
double CP = CENT / VC;
$CAPTURE CP
')

dosing <- data.frame(ID = seq_len(N), time = 0, amt = dose_vec,
                     rate = dose_vec / INF_DUR, cmt = 1, evid = 1)
idata  <- data.frame(ID = seq_len(N), CL = CLi, VC = Vci, Q = TVQ, VP = TVVp)

sim <- mod |> data_set(dosing) |> idata_set(idata) |> obsonly() |>
  mrgsim(tgrid = SAMPLE_TIMES, recsort = 3) |> as.data.frame()
sim$DAY <- DAY_OF_TIME[match(round(sim$time, 6), round(SAMPLE_TIMES, 6))]

ipred <- pmax(sim$CP, 0)
dv    <- pmax(ipred * (1 + rnorm(nrow(sim), 0, PROP_ERR)), 0)

# TRAP: BLQ. True concentration below LLOQ is reported as DV = 0, BLQ = 1.
blq <- as.integer(ipred < LLOQ)
dv  <- ifelse(blq == 1, 0, signif(dv, 4))

## ---- assemble ----------------------------------------------------------
subj <- data.frame(ID = seq_len(N), DOSE = dose_vec, WT = round(wt, 1),
                   ALB = round(alb, 2), CRCL = round(crcl, 1))
obs_rows  <- data.frame(ID = sim$ID, DAY = sim$DAY, TIME = sim$time, DV = dv,
                        AMT = 0, subj[sim$ID, -1], BLQ = blq)
dose_rows <- data.frame(ID = seq_len(N), DAY = 0, TIME = 0, DV = NA_real_,
                        AMT = dose_vec, subj[, -1], BLQ = 0L)
dat <- rbind(dose_rows, obs_rows)
dat <- dat[order(dat$ID, dat$TIME, -dat$AMT), ]
dat$ROWID <- seq_len(nrow(dat))                       # the record key outliers are reported in

# TRAP: decimal-slip outliers, DV x10 at subjects 5/50/95, day 7.
is_out <- with(dat, ID %in% c(5, 50, 95) & AMT == 0 & DAY == 7)
dat$DV[is_out] <- signif(dat$DV[is_out] * 10, 4)

write.csv(dat, out_csv, row.names = FALSE, na = ".")

## ---- 3. sanity checks --------------------------------------------------
k10 <- TVCL / TVVc; k12 <- TVQ / TVVc; k21 <- TVQ / TVVp
s <- k10 + k12 + k21
thalf <- log(2) / (0.5 * (s - sqrt(s^2 - 4 * k10 * k21)))
obs <- dat$AMT == 0
cat("wrote", normalizePath(out_csv), "\n")
cat(sprintf("terminal half-life (70 kg): %.1f days\n", thalf))
cat(sprintf("BLQ: %.1f%% of observations\n", 100 * mean(dat$BLQ[obs] == 1)))
cat(sprintf("r(WT, ALB) = %.2f   r(WT, CRCL) = %.2f\n", cor(wt, alb), cor(wt, crcl)))
cat("outlier ROWIDs (copy into truth.yaml):", paste(dat$ROWID[is_out], collapse = ", "), "\n")

## ---- optional EDA plots (they mark the traps, so never ship them) -----
if (make_plots) {
  figdir <- file.path(script_dir, "figures")
  dir.create(figdir, showWarnings = FALSE)
  d <- read.csv(out_csv, na.strings = ".")
  o <- d[d$AMT == 0, ]

  png(file.path(figdir, "spaghetti-by-dose.png"), width = 1100, height = 420, res = 110)
  op <- par(mfrow = c(1, 3), mar = c(4, 4, 3, 1), oma = c(0, 0, 2, 0))
  for (dz in DOSES) {
    sub <- o[o$DOSE == dz, ]
    pos <- sub[sub$DV > 0, ]                          # log scale: drop BLQ zeros
    plot(NA, xlim = c(0, max(o$TIME)), ylim = range(pos$DV), log = "y",
         xlab = "Time (days)", ylab = "Concentration (mg/L)", main = sprintf("%d mg", dz))
    for (id in unique(pos$ID)) {
      p <- pos[pos$ID == id, ]
      lines(p$TIME, p$DV, col = adjustcolor("steelblue", 0.35))
    }
    out <- sub[sub$ID %in% c(5, 50, 95) & sub$DAY == 7, ]
    points(out$TIME, out$DV, col = "red", pch = 19, cex = 1.2)
  }
  mtext("Concentration-time by dose; red = injected outliers", outer = TRUE, cex = 0.9)
  par(op); dev.off()

  cv <- d[!duplicated(d$ID), ]
  png(file.path(figdir, "covariates.png"), width = 1100, height = 380, res = 110)
  op <- par(mfrow = c(1, 3), mar = c(4, 4, 3, 1))
  hist(cv$WT, col = "grey80", border = "white", main = "Body weight", xlab = "WT (kg)")
  for (v in c("ALB", "CRCL")) {
    plot(cv$WT, cv[[v]], pch = 19, col = adjustcolor("black", 0.4), xlab = "WT (kg)",
         ylab = v, main = sprintf("WT vs %s  (r = %.2f)", v, cor(cv$WT, cv[[v]])))
    abline(lm(cv[[v]] ~ cv$WT), col = "red", lwd = 2)
  }
  par(op); dev.off()
  cat("figures written to", normalizePath(figdir), "\n")
}
