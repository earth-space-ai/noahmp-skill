# Noah-MP Skill

> **⚠ Don't read this skill as a human.** It is written for AI coding agents
> (Claude Code, Codex, Cursor, Aider, Cline, or any agent that can read files
> and run shell). Open it through an agent and let the agent drive — paths,
> module loads, configure keystrokes, build-failure remediation, and the
> dependency test are all designed to be executed by the agent, not typed by
> you. The doc-map and phase blocks are machine-checkable, not tutorial prose.
>
> **Starting prompt — paste into your agent of choice:**
>
> ```
> Read SKILL.md in this repo, then drive the Noah-MP / HRLDAS workflow that
> matches my request below. Treat the skill as authoritative: follow its
> doc-map to load the right reference/*.md, honor the USER GATE markers
> (ask me only at those points), and use examples/test_tacc_deps.sh and the
> AI-native playbook in reference/setup-tacc.md when the target is TACC ls6.
>
> When you invoke examples/test_tacc_deps.sh, pick the flags from my request:
>   --clone           if I'm starting from a fresh ls6 login (almost always)
>   --clone --forcing if my request mentions NLDAS-2, 2D, CONUS, or any
>                     regional/state-scale domain (Texas, California, etc.)
>
> My request: <one sentence — e.g. "set up Noah-MP on TACC ls6 from a fresh
> login through a built hrldas.exe", or "plan a Texas 12.5 km NLDAS-2 run",
> or "add BTRANXY to LDASOUT">.
> ```

A progressive-disclosure skill for the [Noah-MP](https://github.com/NCAR/noahmp)
land surface model and its [HRLDAS](https://github.com/NCAR/hrldas) offline
driver.

> **Disclaimer:** this skill is a **helper for new users** who want to get
> their hands dirty with Noah-MP quickly. It is **not** a gold-standard
> reference and should not be relied on for production decisions, scientific
> publication, or code correctness claims. The content was assembled with AI
> assistance and AI can make mistakes (wrong paths, drifted line numbers,
> stale namelist fields, hallucinated flags). Always cross-check against
> upstream `NCAR/noahmp` and `NCAR/hrldas` and the tech note before acting.

> **Maintainer of Noah-MP:** Cenlin He (cenlinhe@ucar.edu), NCAR/RAL
> **Skill author:** Koutian Wu (ktwu01@gmail.com)
> **Skill version:** 0.1.0

## What This Is

A self-contained knowledge package that teaches AI coding agents how to
**install, compile, run, modify, debug, and contribute to** Noah-MP, covering
the standard refactored Version 5 codebase and the HRLDAS offline driver.
Humans read the disclaimer and the agent's output — the agent reads the rest.

The skill captures the **procedural knowledge** that is normally only
transmitted by working alongside an experienced Noah-MP developer: the order
in which to push a coupled hrldas+noahmp commit, why you should never run
`hrldas.exe` inside the source tree, and the file-by-file chain required to
add a new output variable.

**Progressive disclosure:**
- `SKILL.md`, routing hub: decision tree, repo layout, quick start, critical rules
- `reference/*.md`, deep-dive docs loaded on demand

## Contents

| Document | What's inside |
|----------|---------------|
| `SKILL.md` | Entry point, decision tree, repo layout, quick start, critical rules |
| `reference/designing-a-run.md` | Turn an underspecified user request into a scoped, runnable plan: the seven offline-run parameters, defaults vs. ask, domain sizing, spin-up, resolution-vs-forcing honesty check, plan-doc template |
| `reference/getting-started.md` | Repo structure, submodule clone, libraries, configure, compile, what success looks like |
| `reference/architecture.md` | v5 modular layout, derived types, `kind_noahmp`, module families |
| `reference/running-single-point.md` | Single-site simulation: forcing, namelist, executing, viewing output |
| `reference/running-2d-domain.md` | CONUS NLDAS-2 simulation: pre-processing, `create_forcing.exe`, parallel run |
| `reference/custom-output.md` | Adding a new output variable end-to-end (BTRANXY example, v4.5 vs v5) |
| `reference/contributing-pr.md` | Fork, branch, submodule push order, pull-request review |
| `reference/debugging.md` | Compile, runtime, water-balance failure modes |

## Sources and acknowledgment

**Gold-standard references for Noah-MP** (use these to cross-check anything in this skill):
- Noah-MP v5 tech note: He et al. 2023, doi:10.5065/ew8g-yr95
- NCAR/noahmp repository: https://github.com/NCAR/noahmp
- NCAR/hrldas repository: https://github.com/NCAR/hrldas
- KW-Mod-Tutorials/Noah-MP notebooks (Cenlin He's tutorials): https://github.com/ktwu01/KW-Mod-Tutorials
- NCAR RAL Noah-MP tutorial short course at AMS 2024 (slides): https://ral.ucar.edu/events/2024/ams-2024-short-course-noah-mp-land-surface-model-tutorial
- NCAR RAL Noah-MP tutorial event agenda (slides): https://ral.ucar.edu/events/5249/agenda

This skill is borrowed and learned from the Noah-MP tutorial notebooks
written by **Cenlin He** (NCAR/RAL, Noah-MP maintainer): the single-point,
2D NLDAS, custom-output, and pull-request notebooks distributed in
`KW-Mod-Tutorials/Noah-MP` (`Note1` through `Note4`). The procedural
knowledge (`bondville.dat` format, `create_forcing.exe` pipeline,
`BTRANXY` end-to-end IO chain, the submodule-first push order) is Cenlin's;
this skill restructures it for agent use.

Additional credits:

- **Cenlin He** (NCAR/RAL) and the **NCAR Noah-MP team** for maintaining
  [NCAR/noahmp](https://github.com/NCAR/noahmp), writing the v5 tech note
  (He et al. 2023, doi:10.5065/ew8g-yr95), and curating the refactored Version
  5 codebase that this skill teaches.
- The **NCAR HRLDAS** maintainers ([NCAR/hrldas](https://github.com/NCAR/hrldas))
  for the offline driver, the namelist conventions (including
  `docs/README.single_point` and `docs/README.NLDAS`), and the build chain
  this skill walks new users through.
- **Zesen Huang** for [laps-skill](https://github.com/huangzesen/laps-skill)
  and the xhelio family, the progressive-disclosure layout this repo borrows.

Any errors, oversimplifications, or out-of-date claims in this skill are the
skill author's responsibility, not the upstream community's.

## Install

This skill follows the same layout as
[laps-skill](https://github.com/huangzesen/laps-skill) and the xhelio family
(`xhelio-cdaweb`, `xhelio-spice`, `xhelio-pds`):

```
noahmp-skill/
├── SKILL.md              ← routing hub (read first)
├── README.md             ← this file
└── reference/            ← deep-dive docs
```

To use with a Claude Code or LingTai agent, drop the directory into your
skills library and refresh.

## License

MIT. Noah-MP itself is governed by the NCAR/noahmp license, see
https://github.com/NCAR/noahmp/blob/develop/LICENSE.txt.
