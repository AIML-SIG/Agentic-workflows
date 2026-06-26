# Albumin as a confounded covariate

**Failure mode.** Albumin correlates with the true driver (weight) but doesn't
cause clearance. Univariate screening flags it; a conditional test clears it.
Catches workflows that screen covariates one at a time.

**Injection.** Generate albumin correlated with weight, zero effect on CL. Turn
the correlation up to make it harder.

**Correct handling.** Test albumin with weight already in the model, find nothing,
drop it.

**How it surfaces.** The SAP names ALB in the candidate covariate set on CL
(§2), so the workflow is legitimately prompted to consider it — as a real
defensively-written SAP would. The trap is whether it conditions on weight
before believing the univariate signal. Scored via the `cov_effects` nested-map
item: ALB is a decoy, so reporting an albumin effect on any parameter is an
unmatched key (scores 0) and is flagged as a trap.
