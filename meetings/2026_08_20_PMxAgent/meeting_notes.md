# Agentic Workflows in Pharmacometrics — Meeting Notes

**Date:** 2026-08-20 · **Presenter:** Peter Bloomingdale · **Topic:** PMxAgent
**Format:** Introductions → working group updates → PMxAgent presentation.
**Cadence:** 3rd Thursday of each month, 12:00 noon ET.

> A working subgroup of the [ISoP AI/ML SIG](https://www.isop.org/special-interest-groups/aiml-sig). Repo: [AIML-SIG/Agentic-workflows](https://github.com/AIML-SIG/Agentic-workflows) · [Discussions](https://github.com/AIML-SIG/Agentic-workflows/discussions).

---

## Introductions

---

## Working group updates

- **GitHub.** We are looking for members to participate in the [GitHub repo](https://github.com/AIML-SIG/Agentic-workflows): Discussions, issues, and pull requests. Introduce yourself, claim a lane, and contribute where you can.

- **Benchmarking.** We're going to start a biweekly meeting focused on building the benchmark. To join, please attempt running the first scenario here: [AIML-SIG/Agentic-workflows#33](https://github.com/AIML-SIG/Agentic-workflows/issues/33). You don't need a passing score. Reporting what blocked you counts.

- **Call for presenters (through end of 2027).** We meet every 3rd Thursday of the month at noon. We are putting together a sign-up sheet so presenters are lined up from now through the end of 2027. The sheet already records the [launch (2026-06-25)](../2026_06_25_launch/meeting_summary.md) and Ari's [Modus presentation (2026-07-23)](../2026_07_23_modus/meeting_summary.md). Open slots live in [`meetings/presenter_signup.xlsx`](../presenter_signup.xlsx). Please reach out to claim a date.

---

## PMxAgent presentation

**Repo:** [peterbloomingdale/PMxAgent](https://github.com/peterbloomingdale/PMxAgent)

Peter Bloomingdale (with co-author Antari Khot) presented **PMxAgent**, an open-source agentic platform for developing and deploying specialized agent-callable pharmacometric tools.

AI agents are transforming computational workflows, yet pharmacometric analyses remain largely manual: data wrangling, custom scripts, and specialized software. PMxAgent uses Docker to orchestrate an R-based API server alongside a Python-based Model Context Protocol (MCP) server. The MCP server generates agent-callable tools from OpenAPI specifications, so pharmacometric functions become discoverable and usable by AI agents (Cursor, Claude Code, and any other MCP-compatible client).

Five tools illustrate the platform:

| Tool | What it does |
|------|----------------|
| **NCA** | Non-compartmental analysis via PKNCA (Cmax, Tmax, AUC, half-life) |
| **ER** | Exposure-response modeling (model selection by AIC) |
| **PK** | Pharmacokinetic simulation via mrgsolve (1- or 2-compartment IV) |
| **DATA** | Standardization of raw files to CDISC ADPC format |
| **LIBRARY** | Population PK datasets from published `nlmixr2lib` models |

As a proof-of-concept, PMxAgent orchestrated a multi-step workflow: PK simulation of 60 subjects across three dose groups, NCA to derive individual exposure metrics, then exposure-response analysis.

To evaluate accuracy and reproducibility, the agentic NCA workflow was benchmarked against four frontier AI agents across **182 drugs** and **1,820 simulated subjects**, using PKanalix as the reference. PMxAgent's NCA accuracy (**98.3%**) matched or exceeded that of all frontier agents evaluated. Results were deterministic and reproducible; GPT and Claude agents, by contrast, performed NCA by generating new code on each run.

PMxAgent is designed as an extensible foundation for integrating pharmacometric tools into human-supervised AI-driven workflows, with the reproducibility, transparency, and documentation required for model-informed drug development.

**Try it:** [github.com/peterbloomingdale/PMxAgent](https://github.com/peterbloomingdale/PMxAgent)
