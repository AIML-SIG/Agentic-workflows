# Agentic Workflows in Pharmacometrics — Meeting Summary

**Date:** 2026-07-23 · **Presenter:** Ari · **Co-host:** Peter
**Format:** Introductions → Modus framework presentation → open Q&A / working discussion.
*(The call ran ~98 min across two segments — the free-tier meeting hour cut us off, so we reconvened for a second session.)*

> A working subgroup of the [ISoP AI/ML SIG](https://www.isop.org/special-interest-groups/aiml-sig). Repo: [AIML-SIG/Agentic-workflows](https://github.com/AIML-SIG/Agentic-workflows) · [Discussions](https://github.com/AIML-SIG/Agentic-workflows/discussions).

---

## TL;DR

Ari walked the group through **[Modus](https://www.aripritchardbell.com/blog/2026-05-12-modus)**, a framework for running agentic pharmacometrics analyses, and the **benchmark** that's tightly coupled to it. The core idea: instead of hand-tuning many specialized sub-agents, move all the domain expertise into a single, human-readable **task library** (a JSON file), and drive generic, disposable agents through it in a loop. The recurring themes were **traceability**, **context engineering**, and **where the human belongs in the loop**. Everyone is invited to contribute — especially to the benchmark scenarios and the shared rule library.

---

## Part 1 — The presentation

### Framing: three questions
Three questions the group will help answer over the coming months:
1. **What do we actually need to build** around these agentic systems? (Ari's own path: copilot → multi-agent system → Modus.)
2. **How do we evaluate the agents?** Not just "did the software converge" — the harder, more valuable target is **decision-making and confidence**.
3. **Where should the human be** — surgically placed at key decisions, or fully autonomous end-to-end?

### Foundations (for the newcomers)
- An **LLM is just a function**: text in, text out. Reliable **structured output** (e.g. a tool name + arguments in JSON) is what lets you pipe a model's output straight into an execution environment.
- An **agent** wraps that function in a harness that can loop, run shell/code, search the web, hit APIs, and call other models/agents — so the human steps *outside* the inner loop. This is the "year of the agent" shift: once structured output became reliable, you could build a real harness around it.
- Modern hosted models increasingly have **tool use built in under the hood** — you ask a question, it quietly uses tools and comes back, which greatly improves reliability over a bare LLM that could only hallucinate.
- Agents can be **injected into code as functions** rather than always chatting turn-by-turn — e.g. `claude -p` (pipe a prompt in headless mode, get a response packet back) used like a function inside a workflow. Ari mostly uses **Claude Code**, also **Codex**, plus open-source harnesses.
- Key nuance: you can *usually* swap an agent in wherever you'd use a bare LLM, **but it's often overkill** — it inflates the context window, burns tokens, and introduces variance you then have to audit (unrolling every loop to see where it went wrong). Use a plain LLM for discrete tasks (e.g. task extraction), where one input → one output lets you hone sensitivity precisely.

### Last year's approach (ACoP): multi-agent orchestration
*(Background: Ari's [ACoP 2025 write-up](https://www.aripritchardbell.com/blog/2025-10-16-ACoP).)* An **orchestrator agent** (the Claude Code / copilot you interact with) coordinated the workflow:
- A first **LLM step extracted a structured task list** from the analysis plan so downstream agents could iterate down it.
- A **summary/context file** captured study context (schedule of assessments, mechanism of action, etc.) so agents weren't working from raw data alone.
- Specialized **sub-agents** — one per task (dataset building, EDA, structural modeling, random effects, covariate modeling…), each with a task-specific prompt.
- A separate **reviewer agent** that did *none* of the work itself (fresh perspective) — this measurably improved results — with an option to **escalate to the human** via the orchestrator.
- A final **report writer** that used all artifacts plus example reports to produce the report.

It produced organized output, but **improving the system was hard**: expertise was scattered across many sub-agent prompts, so it was difficult to trace *why* an end result was bad.

### This year's approach: Modus + context engineering
The central pivot — pull all the specialized context out of the sub-agents and into **one task library** (a JSON file) — is written up in full on the blog: **[Modus](https://www.aripritchardbell.com/blog/2026-05-12-modus)**.

- **Inspiration:** an Anthropic blog post (and their London/SF talks) on this "fresh-context loop" pattern seeded the task-library idea; Anthropic have built their own version with workflow commands. Because Claude is built to run *as* an agent (it can spawn sub-agents but doesn't cleanly instantiate a brand-new agent), Ari's take is a very simple **shell script that loops a `claude -p` call with different prompts** — the "**Ralph loop**" — engineered further by keeping state in files.
- **The library = shared expert consensus.** The minimal layer of domain knowledge an off-the-shelf agent won't have (e.g. "always use a log y-axis for concentration plots"). That layer is *shrinking* as models get smarter, but edge cases remain. One text file everyone can review, agree/disagree with, and contribute to on GitHub.
- **Each task entry has fields:** `depends_on` (ordering), `rules` (short things the agent gets wrong consistently), `file preferences` (the exact outputs you want — otherwise it makes whatever it thinks it needs), and `verify` (a self-check loop it runs after finishing).
- **The base prompt** is generic but *hefty*: general execution rules telling each agent to pick the next task, read upstream dependencies from the workspace, read the progress so far, load examples, execute, and write its output.
- **The loop:** each iteration spins up a **brand-new, fresh-context agent**, hands it the base prompt + task library + workspace; it completes **one** task, writes results + a one-line progress-file entry, flips its task to `done`, and exits back to the shell. The **workspace is the only memory** — which is exactly what gives full auditability.
- **Why fresh agents:** long conversations blow up the context window into the "dumb zone" (models handle huge contexts but aren't *good* at them). Keeping each agent's context small and curated is the whole point; the manual curation of task size matters.
- **It's really a graph.** The `depends_on` fields form a directed (mostly acyclic) graph the loop walks — and agents can *flip an upstream task back to false* (e.g. if covariate review reveals the structural model is wrong), triggering a redo, so it's not strictly a DAG.

### Skills vs. the task library
Skills (which emerged *alongside* this work — they didn't exist when Ari started) are a great example of **precision context engineering** via **progressive disclosure** (you point the agent at a packet of text/scripts and *most of the time* it goes and reads it only when needed). The catch: a skill *installed* on an agent shows up in the base prompt for *every* context. Modus wants context to appear **only for the relevant task**, so:
- Short rules go in the task library's `rules` field.
- Heavier skill-style context (a whole example script) lives in an **examples folder** the library points to — `use example from examples.eda.plots.r`. Not strictly enforced, but the agent reliably reads it.
- The two are fully compatible — you can point a task at an existing skill.

### The benchmark (tightly coupled to Modus)
To demo Modus you need a scenario to run it against, so the framework and benchmark are tightly coupled. In pharmacometrics we're lucky to have **simulation** — we can invent scenarios where we know the ground truth. The risk is they get too *toy-like*, which is a standing call to action.

- **Scenario:** a fictitious pop-PK study (3 doses, IV infusion, PK only), with a synthetic analysis plan describing a monoclonal antibody.
- **Deliberate traps:** body weight is the true covariate (on clearance/volume) but is also **loosely correlated with albumin** and **not** correlated with (creatinine) clearance — so an agent that tries to model the albumin covariate without testing properly falls in. Plus a few deliberately **obvious outliers** (three points). Subtle enough that a pharmacometrician catches them but an agent might skip.
- **Baseline vs. Modus:** baseline = a plain agent told to "do what the analysis plan says"; Modus = the framework. Both are run **headless** by command line, both emit a **run log** (every turn — painful to read but full traceability) and are asked for a **submission** in a fixed format so results can be scored formally.
- **Results:** with **Claude Opus 4.8**, the baseline actually **passed everything** (found weight as the covariate for clearance & volume, rejected both traps, found the outliers) — effectively a **null case** where baseline did fine. Modus scored about the same. Ran each **3×**. Scores weren't 100% only because of parameter *precision* — a bit of a red herring; the scoring shouldn't be *only* about precision.
- **The real difference is process, not score:** Modus produces a clean, per-task **workspace** (a sub-folder per task, the exact requested artifacts, some interim artifacts, a **progress file** summarizing each task, and a **git commit per task**); the baseline is a reproducible-but-messy pile of R scripts. Both are traceable/re-runnable, but Modus is auditable at a glance. **Traceability** is the win.
- **Operational finding:** on these long runs (EDA + pop-PK + covariates), **5 runs just failed** across Opus and Sonnet. Notably **Sonnet 5** tried to hand a task off to a background process and then never fired the function call — after 30–40 min of work — likely because context got too long to act intelligently. When it fails mid-run there's no clean repair. Runs use `--dangerously-skip-permissions` + sandboxing; the failure was **not** permission-related.

---

## Part 2 — Continuation & working discussion

### Modus is model-agnostic (and a surprise leaderboard result)
- The "orchestrator" is just the human's assistant (Ari uses Claude Code) — a convenience so you don't run `run.sh` by hand. The task agents are **generic**; nothing special about them beyond the context they're injected with.
- Because the framework wraps the model, you **plug in new/better models as they ship** — the framework is agnostic to the agent/model. Ari runs non-Claude models via **[pi agent](https://pi.dev)** (a lightweight harness with the same properties — headless mode, bash, read/write files, run code) with backends served through **[OpenRouter](https://openrouter.ai)** (Claude Code is tricky to point at non-Claude backends).
- **Surprise:** in this one scenario, **pi + GLM 5.2 outscored Claude Opus** — and GLM cost **< $2** to run. Ari presented Opus/Claude Code as the headline because it's one of the most capable model+harness combos, but the leaderboard is genuinely plug-and-play.
- **Fable** tends to trip its **biological-research guardrails** on meaningful pharmacometrics work and fall back to Opus 4.0.
- **Proprietary data path:** you *can't* send proprietary data to OpenRouter, so for real data the route is **agents on Amazon Bedrock / AWS** (which is also how Claude is used internally) — swap in a Bedrock agent. The point is a platform where, given good benchmark scenarios, you can run *all* the options and see what's most reliable.
- **Cost/leaderboard reality:** Ari has been doing this **out of pocket** — a Claude subscription (timing the usage windows) plus the very cheap GLM runs. Leaderboard-upload code lives in a **dev branch**; results so far are ~3 runs each.

### Regulatory / submission concerns
- *Concern raised:* model-version variance across vendors/updates — is the model version part of an FDA submission?
- *Answer:* the **run log records the model version** at the start, but more importantly you **don't submit the AI** — you submit the **workspace**, and a human **re-runs all the generated code** (R, etc.) as QC and provides *that*. Everything is saved; the framework is designed so a colleague can reproduce it with no AI involved. Variance across versions is exactly *why* the scores matter — you want the highest-scoring, most-trustworthy model, and that will keep changing.

### Measuring what matters — a gradient of metrics
1. **Sim–estimation accuracy** (easy — we know the truth) — useful, belongs in the score, but shouldn't dominate it.
2. **Did it catch the seeded pathologies** (outliers, traps we deliberately planted)?
3. **Were the decisions good ones we agree with?** (harder to score)
4. **End-to-end decisions** (e.g. final dose recommendation vs. what a real pharmacometrician chose on a real dataset) — the real trust signal.

### Human-in-the-loop philosophy
- Goal: **self-reporting + confidence scores** from the model — it should make each decision clearly and attach a confidence, so **deterministic code** can route **low-confidence decisions to a human**. Humans "surgically placed" at key decisions — never hand-holding every step, but never fully out of the loop.
- **LLM-as-judge:** tempting but tricky — its verdicts aren't unanimous, so it adds **another layer of variability** (is the judge aligned with *your* judgment?). It needs an agreed-upon **rubric** living in the benchmark repo. Consensus: useful as a **flag / extra layer** (even getting to ~50% helps), not a replacement — and building a good judge is itself non-trivial (same version-variance problem).

### Better benchmark data
- Move beyond toy synthetic data toward scenarios derived from **publications**, and — even better — **real pharmacometrics reports + regulatory decisions** (sometimes available coupled together). Replicating what a human actually did is the **gold standard**.
- Right now everything's open — you could open the truth file and "score 100." Future: hide truth files in a **private repo** so agents submit results and get back **only a score** (**blinded testing**), preventing gaming — echoing dedicated benchmarking outfits (e.g. **SWE-bench**, τ-bench — "billion-dollar companies built around benchmarking"). A good uncheatable benchmark is most of what you need to then optimize agents.

### Architecture note
- Peter raised the "loops → **graph-oriented** architectures" trend. Ari: **Modus already is a graph** — the task library is a DAG-ish structure via `depends_on` (he calls it a **context graph / context map** in the blog); "loop" just describes how it's executed.
- The **first node is now a scoping/pruning step**: read the analysis plan and **prune the full library** down to what this particular project needs — a pivot from the old "just generate tasks from the analysis plan." This lets you keep a **big, multi-domain library** (e.g. a whole **QSP** cluster with its own background-research steps) and select the relevant sub-graph per project. Because pharmacometrics isn't *that* huge a graph, Ari prefers to **hand-curate** it for good oversight.
- Related hot area: letting the **model control its own context** — powerful, but needs **graph guardrails** or it "diverges into entropy."
- **Model routing / loading:** you *could* route simpler tasks to smaller/cheaper models — but Ari would rather control that by **engineering task size** in the library (split a hard task, combine easy ones).
- An industry **"meta-orchestrator"** pattern (customer support) was noted as an analog: a top-level router over clustered task sets (QSP / pop-PK / etc.).

### On git
- Git is treated as a **must-have** for traceability (and agents are very good at using it — tell it to commit and it just does). The demo showed the Modus run's **7-step git history**: each commit = one task step, with Modus's note and the files it produced. A human can start at, say, **data QC** and re-run each step's scripts to recreate the output — invaluable for reconstruction and for collaborating on a larger team (don't just paste agent output).

---

## Community & housekeeping
- **Getting started:** the site has **getting-started instructions** and a **glossary** (contributed to since kickoff); some cross-linking still needed. **Slides from prior meetings** live in a meetings folder.
- **How to contribute:** everything is open — add to the **docs** and the glossary via **pull requests**; introduce yourself in **[Discussions](https://github.com/AIML-SIG/Agentic-workflows/discussions)** (tracks: **Learning · Tool Discovery · Evaluation & Trust**).
- **Monthly presenters:** about half of each meeting is dedicated to a member presenting their own agentic work (it can be general or sophisticated). **Ari plans to present next month; a presenter is needed for October.** Reach out with ideas.
- **Tools subgroup:** the group curates community tools (e.g. **Modus**, **PMxAgent**) into one readable stack; as a follow-up, a **tools subgroup** will be kicked off — interested members will be contacted.
- **ACoP:** this is the most active SIG in a while; there's a **SIG lunch**, and the working group may organize something within/around it (details TBD).

---

## Get involved
- **Try Modus:** point your agent at the [repo](https://github.com/AIML-SIG/Agentic-workflows) and say "run this scenario" (may need to install some dependencies).
- **Contribute to the benchmark:** bring **real-world failure cases** — issues/traps an agent wouldn't figure out — so they can be encoded as scenarios (ideally toward publication- and report-derived data).
- **Contribute to the task library / glossary / docs** via GitHub pull requests.
- **Introduce yourself** in **[Discussions](https://github.com/AIML-SIG/Agentic-workflows/discussions)** (tracks: Learning · Tool Discovery · Evaluation & Trust).

---

## Links & resources
- **Working group:** [AIML-SIG/Agentic-workflows](https://github.com/AIML-SIG/Agentic-workflows) · [Discussions](https://github.com/AIML-SIG/Agentic-workflows/discussions)
- **ISoP AI/ML SIG:** [isop.org/special-interest-groups/aiml-sig](https://www.isop.org/special-interest-groups/aiml-sig)
- **Blog:** [aripritchardbell.com](https://www.aripritchardbell.com) — [Modus](https://www.aripritchardbell.com/blog/2026-05-12-modus) · [ACoP 2025](https://www.aripritchardbell.com/blog/2025-10-16-ACoP)
- **Tools mentioned:** [pi agent](https://pi.dev) · [OpenRouter](https://openrouter.ai) · Amazon Bedrock (proprietary-data path)
