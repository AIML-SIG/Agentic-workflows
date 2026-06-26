# Working Group Kickoff — Meeting Notes

**Leads:** Ari & Peter
**Attendees:** ~20
**Cadence:** Monthly all-hands; bi-weekly subgroup sessions to spin up later

## Mission

Bring together a community of pharmacometricians to discover, evaluate, and produce agentic workflows, codifying their collective expertise into shared, verifiable standards of practice that grow with the field.

## Intake Survey Takeaways

- Roughly 50/50 split between people here to **learn/network** and people here to **build** (already developing tools). Leads expect this to blur in practice.
- Time-commitment split along similar lines (deep contributors vs. observers) — both seen as valuable.
- ~75% self-reported already using a CLI agent (Claude Code, Codex) or custom workflows. The remaining ~25% (the learners) are essential for keeping terminology and onboarding accessible.

## The Three Working Lanes

1. **Community & shared learning** — roadmap, glossary of terms (standardized nomenclature so everyone is on the same page), curated learning materials. Deliverables targeted over ~6 months.
2. **Discovery & harmonization of tools** — an index of the growing tool landscape and how tools interoperate. Ari's Modus and Peter's PMX Agent seed this; both publishing soon, both open source.
3. **Evaluation & trust** — the most important lane. Building standardized benchmarking datasets, defining how to measure accuracy across agent tools, and forming a community notion of when outputs can be trusted. Lanes "level up" left to right; people self-select by experience.

> **Foundational tools:** Modus (Ari) and PMX Agent (Peter) are both in review / publishing soon, and both will be open source — intended as a shared seed and starting point for the group to build on.

## How to Get Involved

- Everything runs async on **GitHub** (link in the invite/chat).
- Go to **Discussions**, introduce yourself in the Welcome thread, and comment on the lane(s) you want to work on.
- Projects/milestones will be attached as efforts narrow. High-interest areas can become their own projects with a volunteer lead and their own cadence.
- Monthly meetings will open with a 20–30 min presentation (member or external speaker), then organizational updates. **Ari volunteered for the first presentation** — a walkthrough of Modus / the context-engineering approach, with a quick-start repo to be posted in the coming days.
- Meeting-time poll going up: 10am vs. 9am Pacific.

## Key Discussion Themes

- **Scope of benchmarking** (Jeff): scope is "all of it" — from paper-to-implementation reproduction up through full data-analysis workflows. The underlying benchmark-construction principles are general; only the components differ.
- **Benchmark overfitting / public benchmarks**: Marion raised the concern that public benchmarks can be gamed via context management. Ari's response: treat an older, inclusive benchmark set as a "regression-proof" trust signal (any new tool should score well on it), with a rolling window of newer tasks reserved for genuine evaluation.
- **Community variability as a feature** (Brian): five pharmacometricians give five models for the same data — benchmarks should capture that variability rather than assume one ground truth. Cited HealthBench as a model.
- **Educating the broader community**: the group is a more experienced-than-average sample and has an opportunity (and responsibility) to bring the wider ISoP community along through webinars and shared materials.
- **No-ground-truth problem** (Peter): genuinely hard to benchmark when there's no correct answer.
- **Data confidentiality**: a concern was raised about whether real clinical trial data can be used with these agents. This is largely an organizational-policy question rather than a legal one, and depends on data-firewalling so vendors don't train on inputs. Model *access* itself was noted as a significant barrier for many practitioners. Opportunity to write a tutorial/blog on cloud-hosted agents (e.g., via AWS) and compliance considerations (HIPAA/SOC/ISO).
- **Guardrails vs. free rein** (Jeff): big educational gap between handing an agent a dataset with no constraints vs. a guided, skills-based, deterministic approach (e.g., MCP tools for reproducible output). Worth substantial educational material.
- **Labeling/nomenclature of work product** (Jeff): need conventions for transparency — was work done by a human, with a tool, reviewed or not — especially relevant for regulatory submissions.
- **Reproducibility caution**: a general concern was raised that some practitioners drop data into a chatbot, get a figure, and submit it without understanding the underlying code. Building deterministic tooling (e.g., MCP servers) is a path toward reproducible, auditable output.
- **Tool-agnostic focus** (Sejin's closing question): the group builds the *evaluations*, which stay stable, not a bet on any one tool. Tools change weekly; benchmarks let you drop in any agent (Codex, Claude Code, an open-source or hand-coded agent) and test it.

## Open Items / Next Steps

- Members: introduce yourselves and claim a lane on GitHub.
- Vote in the meeting-time poll.
- Ari: post Modus quick-start repo.
- Possible community tutorial on running cloud agents via AWS.
