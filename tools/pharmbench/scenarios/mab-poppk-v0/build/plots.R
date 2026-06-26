#!/usr/bin/env Rscript
# Maintainer EDA plots for PMbench v0 -- HELD OUT of the agent's working directory.
# Producing EDA plots is itself an agent task, so these live in build/figures/,
# never in scenario/. Because they are held out, they may freely annotate the
# injected outliers and the covariate correlations.
#
#   Rscript build/plots.R
# Reads ../scenario/pmb-mab-poppk-v0.csv, writes build/figures/*.png.

args_all   <- commandArgs(FALSE)
this_file  <- sub("^--file=", "", grep("^--file=", args_all, value = TRUE))
script_dir <- if (length(this_file)) dirname(normalizePath(this_file)) else "."
csv  <- normalizePath(file.path(script_dir, "..", "scenario",
                                "pmb-mab-poppk-v0.csv"), mustWork = TRUE)
figdir <- file.path(script_dir, "figures")
dir.create(figdir, showWarnings = FALSE)

d   <- read.csv(csv, na.strings = ".")       # dosing rows carry DV = "."
obs <- d[d$AMT == 0, ]                       # observation rows only
LLOQ <- 0.1
outlier_subjects <- c(5, 50, 95)   # injected day-7 decimal-slip outliers

## ---- 1. spaghetti: concentration-time by dose, log scale ---------------
png(file.path(figdir, "spaghetti-by-dose.png"), width = 1100, height = 420,
    res = 110)
op <- par(mfrow = c(1, 3), mar = c(4, 4, 3, 1), oma = c(0, 0, 2, 0))
doses <- sort(unique(obs$DOSE))
cols  <- adjustcolor("steelblue", 0.35)
for (dz in doses) {
  sub <- obs[obs$DOSE == dz, ]
  pos <- sub[sub$DV > 0, ]                    # log scale: drop BLQ zeros
  plot(NA, xlim = c(0, max(obs$TIME)), ylim = range(pos$DV, na.rm = TRUE), log = "y",
       xlab = "Time (days)", ylab = "Concentration (mg/L)",
       main = sprintf("%d mg", dz))
  for (id in unique(sub$ID)) {
    s <- pos[pos$ID == id, ]
    s <- s[order(s$TIME), ]
    lines(s$TIME, s$DV, col = cols)
  }
  # mark the injected day-7 outliers in red
  out <- sub[sub$ID %in% outlier_subjects & sub$DAY == 7, ]
  if (nrow(out)) points(out$TIME, out$DV, col = "red", pch = 19, cex = 1.2)
}
mtext("Concentration-time by dose (log scale); red = injected day-7 outliers",
      outer = TRUE, cex = 0.9)
par(op)
dev.off()

## ---- 2. covariate distributions and correlation -----------------------
cov <- d[!duplicated(d$ID), c("ID", "WT", "ALB", "CRCL")]
png(file.path(figdir, "covariates.png"), width = 1100, height = 380, res = 110)
op <- par(mfrow = c(1, 3), mar = c(4, 4, 3, 1))
hist(cov$WT, col = "grey80", border = "white", main = "Body weight",
     xlab = "WT (kg)")
plot(cov$WT, cov$ALB, pch = 19, col = adjustcolor("black", 0.4),
     xlab = "WT (kg)", ylab = "ALB (g/dL)",
     main = sprintf("WT vs ALB  (r = %.2f)", cor(cov$WT, cov$ALB)))
abline(lm(ALB ~ WT, cov), col = "red", lwd = 2)
plot(cov$WT, cov$CRCL, pch = 19, col = adjustcolor("black", 0.4),
     xlab = "WT (kg)", ylab = "CRCL (mL/min)",
     main = sprintf("WT vs CRCL  (r = %.2f)", cor(cov$WT, cov$CRCL)))
abline(lm(CRCL ~ WT, cov), col = "red", lwd = 2)
par(op)
dev.off()

cat("figures written to", normalizePath(figdir), "\n")
cat("  spaghetti-by-dose.png\n  covariates.png\n")
