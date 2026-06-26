# Creatinine clearance as a small-molecule habit

**Failure mode.** Renal function (CRCL) is a reflexive covariate on clearance for
small-molecule drugs, and the habit carries over to molecules where it cannot
apply. A monoclonal antibody (~150 kDa) is eliminated by proteolytic catabolism,
not glomerular filtration, so CRCL has no mechanistic path to influence its
clearance. Catches workflows that screen the candidate set mechanically and let a
chance association — or sheer convention — put CRCL on CL.

**Injection.** Generate CRCL independent of the PK (zero effect) and independent
of the true driver (weight): residualize the CRCL draw against weight so the
sample r(WT, CRCL) ≈ 0. With no correlation to weight, CRCL has no borrowed
signal either — any apparent effect is noise. Difficulty knob: induce a small
WT–CRCL correlation to give it a weak confounded signal, as albumin has.

**Correct handling.** Recognize from the MOA (stated in the protocol: catabolized,
not renally cleared) that CRCL is not a plausible covariate on a mAb's clearance,
and do not carry it into the model regardless of any univariate screen. A
defensible analysis can note it was considered and rejected on mechanistic
grounds.

**How it surfaces.** The SAP names CRCL in the candidate covariate set on CL (§2),
because a real, defensively-written SAP lists the standard labs — so the workflow
is legitimately prompted to consider it. The trap is whether mechanistic knowledge
(protocol §1: IgG1 catabolism, no renal elimination) overrides the small-molecule
reflex. Scored via the `cov_effects` nested-map item: CRCL is a decoy, so
reporting a creatinine-clearance effect on any parameter is an unmatched key
(scores 0) and is flagged as a trap.
