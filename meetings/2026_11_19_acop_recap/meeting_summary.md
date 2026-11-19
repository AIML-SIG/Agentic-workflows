# Agentic Workflows WG meeting, 2026-11-19

2026-11-19, 58 min (recording from 08:48 PT). The meeting opened with introductions from new members across pharma, biotech and academia. This is the last WG call of 2026; there is no December meeting, and the WG resumes in January.

**Links:** repo https://github.com/AIML-SIG/Agentic-workflows, Discussions https://github.com/AIML-SIG/Agentic-workflows/discussions, survey https://form.jotform.com/ISoP_Forms/agentic-ai-in-pmx-survey, presenter signup https://forms.gle/roATand9pRqqQ4L86, join the benchmark subgroup https://aiml-sig.github.io/Agentic-workflows/

**Hosts:** Ari and Peter. **Presenting:** Marian (benchmark subgroup report). Speaker attribution below is inferred from content; the recording has no speaker labels.

## Survey (Peter)

- The AIML SIG survey on AI adoption in pharmacometrics went out at ACoP and needs more responses. The aim is a baseline to compare against in a couple of years.
- Peter held off sharing it with this group to avoid biasing it toward heavy users. He asked everyone to take it and forward it to a few pharmacometricians at their company: https://form.jotform.com/ISoP_Forms/agentic-ai-in-pmx-survey

## Group status and ACoP takeaways (Ari, Peter)

- The WG has 166 members, a little over half of them ISoP members, with a jump after ACoP.
- ACoP takeaways: people wanted the how-to details that agentic talks skipped. Access and cost are bigger issues than expected, so local models matter. Data is a bottleneck. The delay is organizational rather than technical. Vendors are testing internally, and the group can make that more transparent.
- Peter: the AIML SIG luncheon was well attended. Adoption is still low but he expects next year to be very different. Vendors are building agentic layers, usually MCP over their validated stacks (Simulations Plus Composer, Certara).
- Ari walked through the three pillars in the repo: shared learning and community (education, with Marian's basics talk and the Ari and Peter tool talks in [`meetings/`](https://github.com/AIML-SIG/Agentic-workflows/tree/main/meetings)), discovering and harmonizing tools, and evaluation and trust (the benchmark subgroup). For 2027 he wants to build an educational library and push on all three pillars.
- Monthly meetings with a speaker continue. To present, email Peter or Ari or use the presenter signup form (https://forms.gle/roATand9pRqqQ4L86). Slots for 2027 start filling in January.

## Benchmark subgroup report (Marian)

- Where the subgroup sits: ISoP, AIML SIG, Agentic Workflows WG, evaluation and trust pillar.
- Joining: run scenario 00 (a simulated PK study with dataset, analysis plan and answer template) any way you like and post the YAML answer in a GitHub issue. Start here: https://aiml-sig.github.io/Agentic-workflows/ Slides and minutes will go to the public repo.
- Framing: trust in a drug claim comes from a controlled trial with prespecified endpoints, and trust in model claims should come from benchmarks with hidden ground truth and prespecified scoring. Existing benchmarks (SWE-bench, Terminal-Bench, HLE, BixBench) do not ask pharmacometric questions.
- Levels of complexity: single decision (spot a NONMEM error), task (structural model, NCA, PK parameter extraction), chained tasks, end-to-end analysis to a submission-ready report.
- Vision: harmonized benchmarks for common PMx tasks built in the open by the SIG, evaluating commercial and open-weight setups, with a leaderboard that tells people how far to trust an agent on a task.
- M1: one agreed benchmark that runs end to end, is scored automatically and lands on a public leaderboard on an ISoP site. Read-only public payload, Docker image fixing the software, harness and model, answer key in a private repo, tokens, cost and runtime recorded.
- M1 setups as presented: Claude Code (Opus, Sonnet) and Codex (Sol, Terra) on personal subscriptions, top tiers excluded on cost. Pi with a top open-weight model (DeepSeek V4.1 Flash or Kimi) plus one model that runs on a Mac Studio class machine (about 5,000 euros), via OpenRouter.
- Open questions: which tasks first, how to define ground truth when the data do not support the simulated model, and when to move from simulated to real data.

## Discussion

- **Real models as data source.** nlmixr2 model library: published reports could serve as pseudo ground truth, and simulating with the reported IIV gives data close to the original. A participant also mentioned published model catalogs and the hundreds of Monolix demo projects (continuous, categorical, time-to-event, count data).
- **Leakage with web access.** Marian worries an agent could find the public model or dataset online. Chain of thought and tool calls should show whether it did.
- **Data pathologies.** Ari described the subgroup's clean-room approach: catalog the kinds of problems seen in real company data (for example concentrations before any dose) and simulate them in synthetic scenarios.
- **Self-reported confidence** as a benchmark (participant suggestion). Ari splits it into two axes: retrospective scoring on known answers, and prospective surfacing of what the human should review, since the human is now the bottleneck. LLM as judge was also raised.
- **Granularity.** A participant wants sub-benchmarks inside the end-to-end flow (QC, unit conversions). Marian worried that an early mistake (2 compartments instead of 3) leaves no ground truth for later steps. Ari: build one rich end-to-end scenario with traps embedded throughout and cut it into stages however you like. Staging correct inputs to intermediate steps is a logistics problem. Tool builders should think about which cut of the scenario would test their tool.
- **Human comparison.** Ari: one publishable metric could be agent versus human. People who do not want to build anything can help by running scenarios themselves.

## Report writing (Peter)

- Peter wants a small group of people with PMx report writing and AI experience. Ari asked for it to start as a discussion in the repo (https://github.com/AIML-SIG/Agentic-workflows/discussions), then become issues and PRs.
- Ari tied it to benchmarking: did the report include the right diagnostic plots, are tables formatted and inside the page in the PDF.
- A participant wants a reviewer agent that flags issues and inconsistencies systematically, since review is a human bottleneck in their team. They will present their team's work in 2027.
- A participant wants to join, with emphasis on doing it without frontier models because of exposure and expected price rises. Peter: his PMX agents paper shows a lower-tier model with MCP tools can match a higher tier.
- Ari: authoring workflows tend to get overrun by the agentic side. LLM writing belongs only in specific places, scaffolded by conventional code.

## Action items

- **Everyone:** take the AIML SIG survey (https://form.jotform.com/ISoP_Forms/agentic-ai-in-pmx-survey) and forward it to a few colleagues.
- **Peter:** open a repo discussion for the report writing group; schedule the reviewer-agent talk for 2027.
- **Marian or Ari:** upload today's slides and minutes to the public repo.
- **Ari and Peter:** fill 2027 speaker slots from January; set WG objectives for 2027.
- **Interested members:** submit scenario 00 to join the benchmark subgroup (https://aiml-sig.github.io/Agentic-workflows/).
