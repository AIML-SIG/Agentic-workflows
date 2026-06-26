# Statistical Analysis Plan (population PK) — PMB-MAB-01

**Synthetic study for benchmarking. No real patients or products.**

This SAP governs the population pharmacokinetic analysis of PMB-MAB-01. It states
the analysis objectives and the reporting deliverables. It does **not** prescribe
the modeling procedure; choice and sequence of analysis steps are left to the
analyst.

## 1. Analysis objectives

1. Develop a population PK model that adequately describes the serum
   concentration-time data across all dose levels, and determine the structural
   disposition model it supports.
2. Estimate the typical values of the primary disposition parameters —
   clearance and central volume of distribution — for a typical subject.
   Report these typical values at a 70 kg reference weight.
3. Assess whether the candidate covariates below explain inter-individual
   variability in the disposition parameters, and determine which parameter each
   supported covariate acts on.
4. Perform quality control of the analysis dataset prior to and during modeling,
   identifying any records inconsistent with the rest of the data.

## 2. Candidate covariates

The following are pre-specified as candidate covariates on the disposition
parameters. They are *candidates* — inclusion in this list does not assert an
effect, nor which parameter an effect would act on; the analysis determines which,
if any, are supported and where.

| Covariate | Column | Units |
|---|---|---|
| Body weight | `WT` | kg |
| Serum albumin | `ALB` | g/dL |
| Creatinine clearance | `CRCL` | mL/min |

The analyst is expected to estimate any covariate relationship that is supported
rather than fix it to an assumed value, to determine which disposition parameter
each supported covariate acts on, and to distinguish a genuine covariate effect
from a spurious association with a correlated variable.

## 3. Data handling

- **Below quantification limit (BLQ).** Records below the assay LLOQ
  (0.1 mg/L) are flagged `BLQ = 1` and carry `DV = 0`. A `DV` of 0 on a BLQ
  record is a censoring flag, **not** an observed concentration of zero. Handle
  BLQ records by a documented, defensible method.
- **Data quality.** Screen the analysis dataset for records inconsistent with a
  subject's own profile and with the population (for example, implausible values
  relative to neighboring timepoints). Document any records excluded or flagged.
- The structural and statistical model form (number of compartments, IIV
  structure, residual error model) is determined by the analysis.

## 4. Deliverables and reporting

Alongside the human-readable analysis summary, emit a machine-readable
`submission.yaml` (see `submission.template.yaml`) with the following keys. These
are the reporting targets; how they are produced is the analyst's decision.

| Key | Meaning | Format |
|---|---|---|
| `structural_ncmt` | Number of disposition compartments in the final structural model | integer |
| `disposition_params` | Typical disposition-parameter values of the final model, at a 70 kg reference weight | map of parameter name → value, in the model's own parameterization (units per Appendix A / above) |
| `error_model` | Residual-error terms of the final model | map of term name → value |
| `cov_effects` | Supported covariate effects, by the parameter they act on | nested map: parameter → covariate column → effect size; `{}` if none |
| `outlier_records` | Records identified as data-quality outliers | list of ROWID strings, e.g. `["418"]`; empty list if none |

Report only what the analysis supports. An objective the analysis does not
address should be left unanswered rather than guessed.

---

# Appendix A — Analysis dataset specification

Dataset: `pmb-mab-poppk-v0.csv`, one row per record, long format.

| Column | Description | Units / coding |
|---|---|---|
| `ID` | Subject identifier | integer 1–120 |
| `DAY` | Nominal study day of the record | integer |
| `TIME` | Time since dose | **days** (the 1-hour infusion ends at TIME ≈ 0.0417) |
| `DV` | Observed serum concentration | mg/L; `.` on dosing rows; `0` on BLQ rows |
| `AMT` | Dose amount on dosing records | mg; `> 0` marks a dosing record, `0` on observations |
| `DOSE` | Assigned dose level for the subject | mg (100 / 300 / 600) |
| `WT` | Body weight | kg |
| `ALB` | Serum albumin | g/dL |
| `CRCL` | Creatinine clearance | mL/min |
| `BLQ` | Below LLOQ flag | `1` = below 0.1 mg/L (then `DV = 0`), else `0` |
| `ROWID` | Stable unique record id (sequential row number) | string; report `outlier_records` using these values |

Dosing convention: each subject has one dosing record (`AMT > 0`) at `TIME = 0`
followed by observation records (`AMT = 0`). The infusion duration is 1 hour
(rate = dose / (1/24) per day). There is no `EVID` column; dosing is identified
by `AMT > 0`.
