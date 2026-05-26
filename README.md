# Noah-MP Skill

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

> ⚠️ **Disclaimer — please read before using this skill.**
> This skill is **not a gold-standard reference**. It is a helper that lowers
> the barrier for new users to **get their hands dirty** with the model. AI
> agents (and the humans drafting this material) make mistakes; commands, file
> paths, namelist options, and physics explanations here can be wrong,
> incomplete, or out of date. **Always cross-check with the official model
> documentation, the source code, and a human expert before trusting any
> output for research, publication, or operational use.**

## What This Is

A self-contained knowledge package that teaches AI agents (and humans) how to
**install, compile, run, modify, debug, and contribute to** Noah-MP, covering
the standard refactored Version 5 codebase and the HRLDAS offline driver.

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

This skill is borrowed and learned from the Noah-MP tutorial notebooks
written by **Cenlin He** (NCAR/RAL, Noah-MP maintainer): the single-point,
2D NLDAS, custom-output, and pull-request notebooks distributed in
`KW-Mod-Tutorials/Noah-MP` (`Note1` through `Note4`). The procedural
knowledge (`bondville.dat` format, `create_forcing.exe` pipeline,
`BTRANXY` end-to-end IO chain, the submodule-first push order) is Cenlin's;
this skill restructures it for agent use.

Additional grounding:

1. **NCAR/noahmp** repository (master branch) and tech note (He et al. 2023, doi:10.5065/ew8g-yr95)
2. **NCAR/hrldas** repository and its `docs/README.single_point`, `docs/README.NLDAS`

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
