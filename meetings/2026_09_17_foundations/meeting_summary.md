# Practical Foundations for Agentic Workflows in Pharmacometrics: Meeting Summary

**Date:** 2026-09-17 · **Presenter:** Marian Klose (Freie Universität Berlin) · **Hosts:** Ari, Peter
**Format:** Working group updates → foundations presentation with live demos → extended open discussion.
*(The call ran ~79 min; the scheduled hour was full of discussion, so the group agreed to continue for another half hour.)*

> A working subgroup of the [ISoP AI/ML SIG](https://www.isop.org/special-interest-groups/aiml-sig). Repo: [AIML-SIG/Agentic-workflows](https://github.com/AIML-SIG/Agentic-workflows) · [Discussions](https://github.com/AIML-SIG/Agentic-workflows/discussions).

---

## TL;DR

After two sessions on sophisticated systems ([Modus](https://www.aripritchardbell.com/blog/2026-05-12-modus) in July, PMxAgent in August), this session deliberately took a step back to the building blocks: what an **LLM** is, what a **harness** adds, what makes it an **agent**, and then the four practical mechanisms for injecting pharmacometric expertise into an off-the-shelf agent (**skills**, **sub-agents**, **MCP tools**, **custom orchestration**), each with a live demo. Two threads dominated the discussion and are worth carrying forward as group work: **the harness is now as important as the model** (and cannot be cleanly deconvoluted from it for benchmarking purposes), and **"validation" of an agent is the wrong target**. The reachable target is generated code that a human can read, re-run, and validate through normal software processes. Both threads landed back on the group's benchmarking effort as the thing that actually addresses the gap.

---

## Working group updates

### ACoP and schedule
- **ACoP is next month.** No dedicated working group outing; the **AI/ML SIG luncheon** (mid-week) is the natural place to meet in person. Grab a table and sit together.
- **No working group meeting in October** because of ACoP. Meetings resume after that, and the call for presenters reopens: reach out to Ari or Peter to take a slot and talk about the platform or tooling you are building.
- Ari and Peter both have scheduled talks at ACoP (Modus, PMxAgent).

### Benchmarking subgroup
- The **first subgroup meeting has happened** and there are **four submissions** so far. The subgroup meets every few weeks and is meant to be genuinely hands-on.
- **How to join:** attempt the open issue on the GitHub repo (also circulated in the meeting invite). Send the results to the organizers, or open a **PR against the repo** if you get all the way through.
- **Current scoring is end-to-end but broken down by category**, and everything, including the truth, is in the public repo. So yes, you could open the answers and give yourself 100%. **That is deliberate for now**, to get people familiar with the mechanics.
- **Where it goes:** once the scenarios are more realistic and robust, the truth moves to a **private repo**; you submit subtask results against a benchmark dataset, get back a score, and the score goes to the **leaderboard**. Details still being worked out.
- A framing raised for that design: build the flow so that **anyone who develops an agent can submit a job**, making it effectively **third-party benchmarking** of agent capability and accuracy.
- Introduce yourself in the repo's **Discussions** forum.

---

## Part 1: The presentation

The presenter is a pharmacist by training and a final-year PhD candidate at Freie Universität Berlin, working on individualized pharmacotherapy in oncology with NLME modeling, Bayesian forecasting in Stan, and ML approaches, and previously founded an LLM-driven exam-prep startup, which is why they were driving LLMs from the command line, R, and Python early.

### The stack: LLM → harness → agent → environment
A layered mental model, simplified on purpose:

- **LLM:** a very large transformer. Text in, numerical vector embedding, forward pass, and out comes a **probability distribution over the next token**, appended and repeated. Hence answers that build up sequentially. Useful scale contrast: **billions of parameters versus the ~10 parameters you fit in a classical pop-PK analysis**. The right mental model is a **text-in, text-out machine**.
- **Harness:** everything that lets it do more than emit text. Web search, code execution, file and tool access, reasoning loops, **permissions**, and **memory/state**. The harness "runs the LLM and gives it hands and eyes", and also gives it limits.
- **Agent:** the harness **run in a loop toward a goal**, acting, checking results, and going back. The goal can be one small task or an entire end-to-end analysis.
- **Environment:** none of this happens in a vacuum. It is your operating system, your files, your codebase, your installed packages and software.

**The key claim, which the group endorsed:** roughly **50% of current innovation is at the harness level and 50% at the LLM level**. A powerful harness with a weaker LLM can match a weak harness with a frontier LLM. Corollary: LLMs and harnesses come from multi-billion-dollar companies and **this group should not be in the business of building harnesses**. Use the off-the-shelf ones (Claude Code, Codex, Positron Assistant) and spend the group's effort **tailoring them to pharmacometrics**, which is the part nobody else will do.

### Discussion: what the diagram is missing
- **Missing layers.** Add a **protocol layer** (agent-to-agent, MCP) for agents talking to each other, and split the environment to expose a **capabilities layer**. "Run NCA", "run pop-PK", "clean datasets" is a *capability*; which software executes it is a separate question. These are being folded in; the diagram is intended as a group artifact to build up.

### Discussion: memory and state as a moving target
- **The validation problem.** If memory/state updates on every run, **how do you validate the system around it?** How that is managed will dictate how trustworthy these systems are. Half-joking answer: maybe turn memory off.
- **Practical tip.** When running experiments, make sure the agent is **not inheriting your personal `AGENTS.md` / `CLAUDE.md`**. Run controlled, so results transfer to someone else who does not have your files.
- **Two different things.** "Memory state" conflates two very different things. **Ephemeral conversation history**, which everyone expects to be thrown away, versus **long-term memory written to files**. The second carries far greater **data-security** risk and deserves to be named separately.
- **Whose property is it.** Memory/state is a property of **both** the harness and the agent, and which side it sits on depends on the question and the harness. Because harness and LLM are **correlated and not cleanly deconvoluted**, this matters directly for how we design evals. "This upcoming year might be the year of the harness."
- **Supporting data point.** On the prototype leaderboard, the best performer was an **open-source model on a minimal open-source harness ([pi agent](https://pi.dev)), beating Claude Code**. The harness/model pairing is doing real work.

### Ways to interact with an LLM
1. **Chat window** (browser or desktop). Already a harness, just a limited one: some reasoning, web search, PDF-to-text, code execution. **All context is managed by hand**, it does not touch your files, and it is **not automatable**.
2. **Vendor harnesses:** Claude Code, OpenAI Codex, Google's Antigravity, Positron Assistant. File access, built-for-long-sessions memory and state, a built-in control loop, and extensibility via skills, sub-agents, and tools. The framing offered: **you never really interact with an LLM directly, you always interact with a harness**.
3. **Custom orchestration:** call the harness from a script for more control (what Modus does), or drop to **plain API calls** when the steps are fully known and you do not need the autonomy.

### Discussion: why the same LLM performs differently across harnesses
An attendee pushed for a concrete answer and the group produced several, which is worth recording as a group explainer:
- **Tool availability.** Build a harness without a web/literature search tool and the same model is simply worse (RAG versus no RAG).
- **Instruction and convention shaping.** A skill file that says "for a VPC use ggplot, use this palette" narrows the search space for the LLM on every run.
- **Deterministic filtering of tool output.** If your R script emits pages of boilerplate and warnings and the harness pipes all of it to the model, that is a lot of noise to process. A harness that filters to the important lines gets better judgment out of the same model.
- **Skill interpretation differs by vendor.** Skills written by and for Claude Code performed **badly** when the same task was run under Codex, because Codex reads skill files differently and skipped words. One of the simplest experiments you can run to see the harness/LLM interaction.
- **Terminology correction worth keeping:** this is not "intelligence" in the harness. Harnesses are largely **deterministic**: system prompts, filtering, context shaping, software engineering around the LLM. "Intelligence" was withdrawn in favor of **capability against a metric**.
- Also settled: who decides the answer has converged, harness or LLM? **A mix of both.**

### What the workflow must deliver for our domain
The framing question: **what must the workflow deliver for us to sign off on its result?** Left column the requirement, right column the mechanism.

| Requirement | Practical support |
|---|---|
| Follows our domain knowledge, established methods, project conventions | **Skills**, **sub-agents**, project instructions, context management |
| Numbers come from executable, tested, reproducible code, never from the neural network itself | **MCP servers** / reusable deterministic tools, example and control scripts |
| Broken into small, checkable chunks (5,000 lines of generated code is not reviewable; you get **AI fatigue** and start rubber-stamping) | **Custom orchestration** (Modus-style), intermediate artifacts |
| Legal requirements and data protection | Not covered today, but everyone has to think about it |
| **Ownership:** a pharmacometrician must still understand and defend the conclusions | A product of all the above |

The ownership point had teeth: it is not acceptable to sit in an FDA hearing and be unable to say why a given modeling step was taken.

### Skills
Reusable instructions and domain knowledge the agent **loads on demand**. At runtime only the **name and description** sit in context; the token-heavy body loads only when the agent decides to invoke it. Motivation is keeping the context window clean (also a cost question), and avoiding the **lost-in-the-middle** effect where instructions buried mid-context get ignored in favor of the beginning and the end.

- This is where pharmacometric conventions live: BLQ handling policy, expected diagnostics, plotting conventions.
- **Two caveats, both important.** Skills **may or may not fire**; loading is somewhat stochastic and it may not pick the skill you expected. And a skill is **an instruction, not a constraint**: "do not access this data folder" can simply be ignored, and has been observed to be. **Skills are not permissions.**
- **Mechanics:** `.claude/skills/<name>/SKILL.md`, a YAML header with `name` and `description` plus a markdown body. Conventions are broadly similar across vendors. **The description is what triggers the skill**, so be precise about when it should load; the body holds the detail.
- **Live demo (the sharpest moment of the talk).** Same pharmacometric task, a genuinely contestable one: a 2-compartment model with **higher OFV but all RSEs under the usual 30% identifiability rule**, versus a 3-compartment model with **lower OFV but slightly above it**. With no skill, the agent picked the **2-compartment** model and gave its reasoning. With a skill added saying *always select on lowest OFV*, it loaded the skill unprompted and switched to the **3-compartment** model. Skills materially change agent behavior.
- **Consequence for the group:** we will need a **standardized, agreed skill set**, and being explicit about something like model selection is going to be a large discussion. One suggestion for next time: **poll the audience first and harvest the human pharmacometrician distribution** before showing the agent's answer.

### Sub-agents
Specialized agents that handle a delegated task **in their own separate context**. Four reasons to use them:
1. **Preserve context** in the main session.
2. **Enforce constraints**, by limiting which tools the sub-agent may use.
3. **Specialize behavior** with a focused system prompt.
4. **Control cost.** Route mechanical, token-heavy work to a cheap model (Haiku) while the main session stays on an expensive one.

As with skills, **delegation is a suggestion driven by the YAML `description`**, not a guarantee. Mechanics: `.claude/agents/<name>.md`, with a richer header that includes the **allowed tools** (for example `WebFetch` if it needs to read the web) and a custom system prompt.

- **Live demo:** asked whether context engineering matters to pharmacometrics, referencing one of the group's manuscripts. The session **paused and delegated to the Haiku sub-agent**, which fetched the page and returned a compact summary. The **8.7k tokens of fetch-and-summarize were paid at Haiku rates, not Opus rates**, and Opus only finalized the answer.
- **Vendor variance:** Claude Code is currently more sophisticated here. Codex has sub-agents but, as far as the presenter knows, not the same specialization via a markdown definition. Caveat on all of this: things move fast enough that six months is a long time.

### MCP servers
The standard way for an agent to connect to extended tools, functions, and data. Analogy offered: **USB-C for agents**.

- **Why it matters for validation:** prompt an agent 10 times to do an NCA and it will creatively write 10 different solutions, which is 10 times the validation work. Point it at a **deterministic function** and you **validate once**. This is the PMxAgent argument.
- **Trend:** vendors will publish their own MCP servers. Already happening (Pumas AI, Certara) alongside scientific projects like PMxAgent, and it will keep growing.
- As with skills and sub-agents: tools are **discovered at runtime** and the agent decides on its own whether to call one. The **docstring** is what it decides from.
- **Local demo, deliberately demystifying.** An MCP server does **not** have to be on the internet. A few lines of Python with **FastMCP**, exposing a single `cmax` tool taking an array of concentrations, is enough. A Python wrapper is sufficient even if your actual functions are in R. Register it with one `claude mcp add` line (project scope, a name, your venv Python, the script path), which writes `.mcp.json`. Then `/mcp` inside Claude Code shows the connected server, the exposed tool, its signature, and the imported docstring. Asked for the Cmax of a patient's measured concentrations, the agent called `cmax` from the demo server and passed the array; the details pane shows exactly that. **All you need to validate is that the input was transferred correctly to the function.**

### Discussion: never pipe data through an MCP boundary
The most operationally useful exchange of the session.
- **The core caution.** MCP **input is emitted token by token by the model and output is ingested token by token**. So pass and receive **small** amounts of data. For anything larger, use a **code-execution tool** so the data is read from disk and handed straight to the deterministic code, and results are written to disk or plotted rather than returned inline. A signature that says "takes data" is a warning sign, because it looks like it can do more than it can.
- **Already addressed in the August talk.** Piping data through invites **transcription errors** as the model rewrites it token by token. The approach there: keep the dataset in a file management system and **pass the location** (for example an S3 path) so the agent reads the file.
- As put in the discussion: "the Hello World of pharmacometric LLM use is figuring out not to pass data directly into the LLM." Everyone has hit this.
- **Caution on third-party MCPs:** an arbitrary MCP server, vendor-built or otherwise, may not have been written with this in mind. Worth checking before trusting one with data.
- **Related question, does an API call differ?** Not fundamentally: the question is whether you get a massive dump or a controlled packet the model can reasonably process, and **that happens in the harness**. **A concrete example:** Claude Code's `WebFetch` does not hand the model raw HTML. It **converts the page to Markdown** to cut tokens and then **truncates** it. A well-designed MCP server should filter comparably. Better still, an MCP that **executes R or Python** returns only what the code prints, so "saved to disk, OK" can be the entire payload.

### Custom orchestration, and when you do not need an agent
- Modus is the example of calling a **vendor harness repeatedly from shell scripts**, which is the main selling point for not relying on the harness alone.
- The counterpoint put on the record: when the steps are genuinely known, **plain API calls are still reasonable**. You do not always need creativity and flexibility.
- **Example:** hundreds or thousands of papers to extract parameters from. Using **[ellmer](https://ellmer.tidyverse.org/)** (R, maintained by Posit), define a **structured output** schema (compound, route of administration, volume, clearance, typed as string or number, each with a field description), call `chat_anthropic()` and `chat_structured()`, and get a tibble back. Hallucinations are possible but on an easy extraction task the results are good.
- **Closing note on this:** knowing when you *do not* need the full power of an agent is a subtle but critical skill if we are going to build these systems up.

---

## Part 2: Extended discussion

### The hardest question: validated, safe tools for clinical use
An attendee asked, from a clinical pharmacology and clinical data science angle, what the biggest challenge is in translating agentic workflows into validated, safe tools for real-world clinical data and decision-making.

- **The presenter:** we are definitely not there yet for production. The core challenge is **reviewability**, and it is a genuine tension. Let it run for three days unattended and you get the full efficiency benefit but cannot review the result. Review every tiny decision and you own the result, but you have given back all of the advantage. **How far to break the work down, and what to accept where, is unsolved.**
- **One view:** tools like Positron Assistant and Claude Science are attacking exactly this by making the **code** the artifact. The code is there, you can re-run the analysis.
- **The clearest statement of the session, from Posit:** generated-but-reviewable, reproducible code is **not the future, it is the present**. Use agents to write code you can **understand, review, and validate through your normal processes**. If anyone is hoping for a magic prompt, magic fine-tune, or magic benchmark that makes a model or harness **"Validated with a capital V"** so you can turn your brain off, that is not within reach, and not something we should be eager to reach quickly. Things are moving fast enough. Use these to accelerate **the deterministic workflows we already have**, at which point "is the agent validated" is largely moot as regards correctness of results.
- **Building on that:** ask an agent for output in a given format and it is pretty consistent about it, so a **workspace where every decision is traceable and every script re-runnable by hand is already available today**, with a fairly low-tier model. The open problem is different: **finding the equivalent of a VPC for an agent**, a way to **aggregate the decisions at a glance**.
- **A second, deliberately counterintuitive point:** in software engineering the position has flipped in about a year, from "if you used an agent, double-check it with human eyes" to the better models being **superhuman at code review**. Plausibly, in the near future, when validating a workflow as fit for purpose, **not having used an agent to review the code, however it was written, could itself be the malpractice**.
- **On the burden of proof:** our industry is conservative enough that we will likely have to **show the data** that code agents outperform humans on these workflows. It will be humbling, people will not enjoy it, and daily users can already see it anecdotally. Showing it is the field's responsibility.

### Do we need benchmarks for the non-coding parts?
A follow-up: the code-review argument is about coding, but pharmacometricians and clinical pharmacologists do plenty that is not coding. If we should not be trying to validate those systems, what is the analogy, and do we need benchmarks there?

- **From Posit, with an explicit caveat that their focus is reproducible code and data analysis, so this sits outside that lane:** **benchmarks are really hard.** Writing evals that reflect what people actually experience is really, really hard. Through vast stretches of 2025, the top coding leaderboards did not match the experience of anyone actually using the models: Claude's frontier model sat around **number 10** behind a stack of others, which was **complete nonsense** at the time. Maybe slightly better now. The caution stands: benchmarks feel like they can solve everything, and so far they have **a checkered record of reflecting reality**.
- **The organizers:** this is precisely the impetus for the group. Build the **consensus** and the **database** as the tangible artifact, so we have a way of **quantifying decisions**. And to be clear about the target: **we are not scoring how well it recovers parameters, we are scoring pharmacometric intuition**, which is bad right now, getting better, but still bad. The database is what lets us measure it.
- **On what code review actually means:** it depends on your objective function. Is the code doing what it needs to do to answer the question? **Even NONMEM has bugs**, so the bar is not perfect code, it is **sufficient testing and sufficient engineering**: unit tests, integration tests, applied to the pieces. Test the parts rather than generating a million lines and running it, or trying to test a million lines after the fact.
- **From an attendee who now spends ~80% of their time as an evaluator:** the community needs to decide **what a "unit of work" is in pharmacometrics** for eval purposes. Some units suit **LLM-as-judge**, some are numerical, some are "write this differential equation" and are deterministic enough that LLMs handle them well, as with coding. Being deliberate about which units have traps and which do not is what makes a good eval. The cautionary example: a benchmark that **caught fire on Twitter** purely because it was expressed wrongly, and vendor system cards that quietly disclose a benchmark was **run on 40 of 250 items**. So how much do you trust that number? The group needs to think about this in more depth.

### Coding assistants versus harnesses: naming and convergence
Prompted by work on a survey to categorize the landscape.
- **Posit's own history:** a year ago they shipped **Positron Assistant**, forked from Copilot. Separately they built **Databot**, an experimental harness of their own, for exploratory data analysis. They liked Databot and did **not** like Positron Assistant; Databot turned out to be much more like Claude Code, and that approach took over. So they doubled down on Databot and **generalized** it beyond EDA to data cleaning, general coding, report writing, and apps. **The built-in coding agent in RStudio and Positron today is that, under the Positron Assistant name.**
- **Convergence:** Positron Assistant, Cursor, Claude Code, and Codex now sit in essentially the same bucket. Even **Copilot** grew an agent mode which became its normal mode. The original autocomplete-style copilots are effectively **dead or outdated**.
- **Posit's differentiator worth noting:** Positron Assistant **plots inline in the conversation, and the agent sees the plot too**. Some users specifically want the figure right there.
- **Posit were invited, and agreed, to take a future presentation slot** on Positron Assistant / Databot. Details offline.

### Claude Science
An attendee asked where it fits: you can connect your own machine, APIs, and MCP servers; it generates code and tracks provenance.
- **Best read offered:** it is a way for **non-programmers** to get Claude Code's flexibility behind a friendlier GUI, with the same underlying functionality, just packaged with a cleaner and more opinionated UI. The counter-bias in the room: everyone on this call codes NONMEM and is perfectly capable of harness-level control, so the packaging costs you flexibility.
- **One anecdote, flagged as a single try shortly after launch, and the product is iterating fast.** The prompt was "some Python routines to do microscopy analysis", nothing more. It ran for ~45 minutes and came back with a **package ready to publish to PyPI**. The surprise was how proactive it was without being told what was wanted, and more so that **the only artifacts left behind were sample PNGs and a tarball**, with the Python code not readily accessible.
- **Counter-observation from others who use it:** they do get the Python or R scripts right there, **plus provenance**, so changes can be followed over time. With provenance plus stored agent traces, you have the history and the components you need; the product is built on top of that.
- **One read on the proactivity:** a double-edged sword, and probably part of how these products score well on benchmarks, but not always what we want.

### Closing takeaways
- **LLMs will fundamentally change how pharmacometricians work.** The presenter does not expect us to be jobless, but the way we work will change.
- **We are not nearly there yet.** Realizing the potential requires real work on **validation, human oversight, and building trust** in the analysis.
- The group's **shared benchmarks** and continuous learning were framed as directly addressing that gap: the way to find out what works for this domain and what does not.
- Lightly consoling coda from the room: pharma adopts technology painfully slowly, so we probably have five to ten years. Hopefully more.

---

## Get involved
- **Join the benchmarking subgroup:** attempt the open issue on the repo (linked in the meeting invite), send your results to the organizers, or open a PR if you complete it.
- **Contribute to the layered diagram:** the protocol layer, capabilities layer, and the memory/state split (ephemeral history versus persisted files) are all open for improvement as a group artifact.
- **Start the standardized skill set discussion:** the model-selection demo shows a skill changes the answer, so the conventions we agree on matter. Expect it to be a long discussion.
- **Take a presentation slot:** no meeting in October (ACoP), and slots reopen after that. Reach out to Ari or Peter.
- **Bring eval design thinking:** what counts as a unit of work, where LLM-as-judge is appropriate, and how to avoid the traps that have made general LLM benchmarks unreliable.
- **Introduce yourself** in **[Discussions](https://github.com/AIML-SIG/Agentic-workflows/discussions)**.
- **Say hi at ACoP**, at the AI/ML SIG luncheon.

---

## Links & resources
- **Working group:** [AIML-SIG/Agentic-workflows](https://github.com/AIML-SIG/Agentic-workflows) · [Discussions](https://github.com/AIML-SIG/Agentic-workflows/discussions)
- **ISoP AI/ML SIG:** [isop.org/special-interest-groups/aiml-sig](https://www.isop.org/special-interest-groups/aiml-sig)
- **Prior sessions:** [Modus (July 2026)](../2026_07_23_modus/meeting_summary.md) · [PMxAgent (August 2026)](../2026_08_20_PMxAgent/meeting_notes.md)
- **Modus write-up:** [aripritchardbell.com/blog/2026-05-12-modus](https://www.aripritchardbell.com/blog/2026-05-12-modus)
- **Harnesses mentioned:** Claude Code · OpenAI Codex · Positron Assistant / Databot (Posit) · Google Antigravity · [pi agent](https://pi.dev) · Cursor · GitHub Copilot · Claude Science
- **Tools mentioned:** [FastMCP](https://github.com/jlowin/fastmcp) (minimal local MCP server) · [ellmer](https://ellmer.tidyverse.org/) (structured output from R) · MCP servers from Pumas AI and Certara
