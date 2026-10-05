# Study protocol and analysis plan: PMB-MAB-01

**Synthetic study for benchmarking. No real patients or products.**

Part 1 describes the study. Part 2 states what the population PK analysis must
deliver. It does **not** prescribe the modeling procedure; the choice and order
of analysis steps are left to the analyst.

# Part 1. Study

## 1. Background and mechanism of action

PMB-MAB-01 is a first-in-human, single-ascending-dose study of a generic
humanized IgG1 monoclonal antibody ("the mAb") directed against a soluble
circulating ligand.

As a typical IgG1, the mAb is eliminated by **proteolytic catabolism**, the
non-specific reticuloendothelial degradation pathway shared by endogenous IgG,
modulated by FcRn-mediated recycling. It is a large protein (~150 kDa) and is
**not filtered by the kidney and not renally eliminated**; renal function is not
expected to influence its disposition. Distribution is largely confined to
plasma and interstitial fluid, consistent with a small central volume and
limited peripheral distribution.

## 2. Study objectives

- Characterize the single-dose pharmacokinetics of the mAb across the studied
  dose range.
- Describe inter-individual variability in exposure.
- Explore demographic and laboratory factors that may explain that variability.

## 3. Population

Healthy adult volunteers. Body weight spans the normal adult range
(approximately 50 to 110 kg). Standard safety laboratory assessments, including
serum albumin and creatinine clearance, are collected at screening.

## 4. Treatment

Single 1-hour intravenous infusion. Three dose levels, 40 subjects each:

| Cohort | Dose | N |
|---|---|---|
| 1 | 100 mg | 40 |
| 2 | 300 mg | 40 |
| 3 | 600 mg | 40 |

Total 120 subjects.

## 5. Pharmacokinetic sampling

Serum concentrations are drawn at: predose, end of infusion, and on days 1, 3,
7, 14, 28, 42, 56, 70, 90, 120, and 150 after dosing. The extended follow-up
(to ~150 days, several elimination half-lives) characterizes the terminal phase.

Bioanalytical assay lower limit of quantification (LLOQ): **0.1 mg/L**.
Concentrations below the LLOQ are reported by the laboratory as below the
quantification limit.

# Part 2. Analysis plan (population PK)

## 6. Analysis objectives

1. Develop a population PK model that adequately describes the serum
   concentration-time data across all dose levels, and determine the structural
   disposition model it supports.
2. Estimate the typical values of the primary disposition parameters
   (clearance and central volume of distribution) for a typical subject.
   Report these typical values at a 70 kg reference weight.
3. Assess whether the candidate covariates below explain inter-individual
   variability in the disposition parameters, and determine which parameter each
   supported covariate acts on.
4. Perform quality control of the analysis dataset prior to and during modeling,
   identifying any records inconsistent with the rest of the data.

## 7. Candidate covariates

The following are pre-specified as candidate covariates on the disposition
parameters. They are *candidates*: inclusion in this list does not assert an
effect, nor which parameter an effect would act on. The analysis determines
which, if any, are supported and where.

| Covariate | Column | Units |
|---|---|---|
| Body weight | `WT` | kg |
| Serum albumin | `ALB` | g/dL |
| Creatinine clearance | `CRCL` | mL/min |

The analyst is expected to estimate any covariate relationship that is supported
rather than fix it to an assumed value, to determine which disposition parameter
each supported covariate acts on, and to distinguish a genuine covariate effect
from a spurious association with a correlated variable.

## 8. Data handling

- **Below quantification limit (BLQ).** Records below the assay LLOQ
  (0.1 mg/L) are flagged `BLQ = 1` and carry `DV = 0`. A `DV` of 0 on a BLQ
  record is a censoring flag, **not** an observed concentration of zero. Handle
  BLQ records by a documented, defensible method.
- **Data quality.** Screen the analysis dataset for records inconsistent with a
  subject's own profile and with the population (for example, implausible values
  relative to neighboring timepoints). Document any records excluded or flagged.
- The structural and statistical model form (number of compartments, IIV
  structure, residual error model) is determined by the analysis.

## 9. Deliverable: `submission.yaml`

Fill in `submission.template.yaml` and save it as `submission.yaml`. These keys
are the reporting targets; how they are produced is the analyst's decision.

| Key | Meaning | Format |
|---|---|---|
| `structural_ncmt` | Number of disposition compartments in the final structural model | integer |
| `disposition_params` | Typical disposition-parameter values of the final model, at a 70 kg reference weight | map of parameter name → value, in the model's own parameterization (units per Appendix A) |
| `error_model` | Residual-error terms of the final model | map of term name → value |
| `cov_effects` | Supported covariate effects, by the parameter they act on | nested map: parameter → covariate column → effect size; `{}` if none |
| `outlier_records` | Records identified as data-quality outliers | list of ROWID strings, e.g. `["418"]`; empty list if none |

Report only what the analysis supports. An objective the analysis does not
address should be left unanswered rather than guessed.

---

# Appendix A. Analysis dataset specification

Dataset: `data.csv`, one row per record, long format.

| Column | Description | Units / coding |
|---|---|---|
| `ID` | Subject identifier | integer 1 to 120 |
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
