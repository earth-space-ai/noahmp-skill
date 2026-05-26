---
name: noahmp
description: >
  Self-contained guide to Noah-MP, the community Noah Multi-Parameterization
  land surface model (NCAR/noahmp). Covers the refactored Version 5 modular
  Fortran codebase, the HRLDAS offline driver, designing a runnable simulation
  from an underspecified user request, single-point and CONUS 2D runs,
  adding custom output variables, and contributing through GitHub pull
  requests. Progressive disclosure: start in this file for routing, drill
  into reference/ for depth.
version: 0.1.0
tags:
  - earth-science
  - hydrology
  - land-surface-model
  - fortran
  - noah-mp
  - hrldas
  - climate
  - nldas
---

# Noah-MP, Complete Guide

> **Disclaimer:** this skill is a hands-on **helper for new users** who want
> to get their hands dirty with Noah-MP quickly. It is **not** a gold-standard
> reference and **should not be relied on for production decisions, scientific
> publication, or code correctness claims**. The content was assembled with
> AI assistance and AI can make mistakes (wrong file paths, drifted line
> numbers, stale namelist fields, hallucinated flags). Always cross-check
> against the upstream `NCAR/noahmp` and `NCAR/hrldas` repositories and the
> tech note before acting on anything you read here.

> **Noah-MP** = Noah Multi-Parameterization land surface model
> Maintainer: Cenlin He (cenlinhe@ucar.edu), NCAR/RAL
> Source: https://github.com/NCAR/noahmp and https://github.com/NCAR/hrldas
> Tech note: He et al. 2023, doi:10.5065/ew8g-yr95
> Model paper: He et al. 2023, GMD 16:5131-5151, doi:10.5194/gmd-16-5131-2023
>
> **Acknowledgment:** the procedural content in this skill is borrowed and
> learned from the Noah-MP tutorial notebooks written by Cenlin He
> (`Note1_Single_Point_Bondville-site`, `Note2_2D_NLDAS2_domain`,
> `Note3_Output_Additional_Variables`, `Note4_Code_Development_GitHub_Pull_Request`),
> distributed at https://github.com/NCAR/hrldas/tree/master/hrldas/docs and in
> the `KW-Mod-Tutorials/Noah-MP` notebook set. This skill restructures that
> material for agent use; the underlying instruction is Cenlin's.

**What Noah-MP does:** Solves coupled land-surface energy, water, and carbon
budgets at a column (single point) or over a grid (2D domain). Provides
multiple physics options (multi-parameterization) for canopy radiation, runoff,
soil moisture, snow, stomatal resistance, vegetation dynamics, etc. Used
operationally inside HRLDAS, WRF, MPAS, NOAA UFS, NASA LIS, WRF-Hydro/NWM.

**Who this skill is for:** Agents, students, and researchers who want to
download, compile, run, modify, debug, and contribute to Noah-MP.

---

## Quick Decision Tree

```
"What do I need?"
│
├─ 🆕 First time. What is Noah-MP and how do I install it?
│  └─ Read: reference/getting-started.md
│     (HRLDAS + Noah-MP submodule clone, configure, compile)
│
├─ 📐 A user gave me an underspecified request ("soil moisture over Texas,
│     12.5 km, on TACC") and I need to turn it into a runnable plan
│  └─ Read: reference/designing-a-run.md
│     (the seven parameters, defaults vs. ask, domain sizing, spin-up,
│      resolution-vs-forcing honesty check, plan-doc template)
│
├─ 🚀 I want to run a single-point simulation (one site)
│  └─ Read: reference/running-single-point.md
│     (forcing format, namelist.hrldas, hrldas.exe, Bondville)
│
├─ 🌎 I want to run a 2D regional simulation (CONUS / NLDAS-2)
│  └─ Read: reference/running-2d-domain.md
│     (geo_em, NLDAS-2 GRIB, create_forcing.exe, parallel run)
│
├─ 📤 I want to add a new output variable
│  └─ Read: reference/custom-output.md
│     (BTRANXY example, v4.5 vs v5 refactor, IO transfer chain)
│
├─ 🔬 I want to understand how Noah-MP v5 is organized
│  └─ Read: reference/architecture.md
│     (NoahmpMainMod, derived types, kind_noahmp, module list)
│
├─ 🤝 I want to submit a pull request to NCAR/noahmp
│  └─ Read: reference/contributing-pr.md
│     (fork, remote alias, submodule push order, reviewers)
│
└─ 🐛 The model won't compile / won't run / gives weird output
   └─ Read: reference/debugging.md
      (compile errors, missing libs, segfaults, water balance)
```

---

## What's Inside Noah-MP (v5+)

```
hrldas/                                    ← top-level driver repo
├── hrldas/                                ← HRLDAS-specific code
│   ├── IO_code/
│   │   └── module_NoahMP_hrldas_driver.F  ← add_to_output lives here
│   ├── run/                               ← run directory; namelist + tables go here
│   │   ├── namelist.hrldas
│   │   ├── NoahmpTable.TBL                ← unified parameter table (v5)
│   │   ├── URBPARM.TBL, GENPARM.TBL, SOILPARM.TBL
│   │   └── hrldas.exe                     ← built executable
│   └── HRLDAS_forcing/                    ← create_forcing.exe (NLDAS pre-processor)
└── noahmp/                                ← Noah-MP submodule (NCAR/noahmp)
    ├── src/                               ← 130+ modular *Mod.F90 files
    │   ├── NoahmpMainMod.F90              ← main physics driver
    │   ├── NoahmpVarType.F90              ← top-level derived type
    │   ├── EnergyMainMod.F90, WaterMainMod.F90
    │   ├── PhenologyMainMod.F90, BiochemNatureVegMainMod.F90
    │   ├── *VarType.F90                   ← state/flux/param sub-types
    │   └── Makefile
    ├── drivers/
    │   ├── hrldas/                        ← HRLDAS coupling layer (IO transfer)
    │   ├── lis/, wrf/, erf/               ← other host model drivers
    ├── parameters/
    │   ├── NoahmpTable.TBL                ← physics + PFT parameters
    │   └── snicar_*.nc                    ← SNICAR snow albedo lookup
    ├── docs/NoahMP_v5_technote.pdf
    └── utility/Machine.F90                ← kind_noahmp definition
```

**For most users:** edit `namelist.hrldas` and `NoahmpTable.TBL`, then run
`hrldas.exe`. Source code edits live in `noahmp/src/` (physics) and
`noahmp/drivers/hrldas/` (HRLDAS coupling).

---

## Critical Rules

1. **Always clone with `--recurse-submodules`.** The `noahmp` source is a
   submodule under `hrldas`. Without it, compilation fails immediately.

   ```bash
   git clone --recurse-submodules https://github.com/NCAR/hrldas
   ```

2. **Push submodule first, then driver.** When committing changes that touch
   both `hrldas/` and `hrldas/noahmp/`, push `noahmp` to your fork first, then
   `hrldas`. The driver repo records the submodule commit SHA, so pushing in
   the wrong order leaves a dangling reference.

3. **Forcing must be UTC.** Single-point observation files (e.g., bondville.dat)
   must be in UTC time; `create_point_data.exe` does not convert local time.

4. **Run experiments outside the source tree.** Copy `hrldas.exe`, `*.TBL`,
   the `HRLDAS_setup_*_d1` initial-state file, and the LDASIN forcing into
   a dedicated experiment directory under a scratch filesystem. Never run
   `hrldas.exe` inside the git checkout, since it pollutes the working tree
   with `*.LDASOUT`, `RESTART.*`, and log files. (Offline HRLDAS does not
   read WRF's `wrfinput`; it initializes from `HRLDAS_setup` or the
   single-point forcing file's state section.)

5. **`make clean && make` after every code change.** Fortran object files are
   not rebuilt reliably without a clean.

6. **Two libraries are required to build:** netCDF and Jasper (jpeg2000). Set
   `NETCDFMOD`, `NETCDFLIB`, `LIBJASPER`, `INCJASPER` in `user_build_options`.

---

## Quick Start (HRLDAS + Noah-MP, single-point)

```bash
# 1. Get the code (submodule pulls in noahmp)
git clone --recurse-submodules https://github.com/NCAR/hrldas
cd hrldas/hrldas

# 2. Configure (pick compiler option; option 5 on NCAR/CISL)
./configure

# 3. Edit user_build_options for netCDF + Jasper paths
$EDITOR user_build_options

# 4. Build
make clean && make >& compile.log
grep -i error compile.log    # should be empty

# 5. Run a provided single-point case
cd run
$EDITOR namelist.hrldas      # set INDIR, OUTDIR, dates, physics options, etc.
./hrldas.exe                 # ~1 min for a 1-year Bondville run

# 6. Inspect output
module load ncview
ncview <YYYYMMDDHH>.LDASOUT_DOMAIN1
```

→ Full walkthrough in `reference/getting-started.md` and
`reference/running-single-point.md`.

---

## Reference Documents

| Document | What's inside |
|----------|---------------|
| `reference/designing-a-run.md` | Turn an underspecified user request into a scoped, runnable plan: the seven parameters every offline run needs, which to default vs. ask, domain cell-count sizing, spin-up strategy, the resolution-vs-forcing honesty check, and the plan-doc template |
| `reference/getting-started.md` | Repos, submodule clone, libraries, `./configure`, `user_build_options`, `make`, what success looks like |
| `reference/architecture.md` | v5 modular layout, `noahmp_type` derived type, `kind_noahmp`, module list, v4.5 → v5 variable glossary |
| `reference/running-single-point.md` | Bondville site, `bondville.dat` format, `create_point_data.exe`, namelist sections (paths, dates, physics options, timesteps), `ncview` |
| `reference/running-2d-domain.md` | NLDAS-2 GRIB download, `extract_nldas.perl`, `create_forcing.exe`, `geo_em.d01_NLDAS0125.nc`, parallel submission |
| `reference/custom-output.md` | BTRANXY end-to-end: `WaterVarType`, `NoahmpIOVarType`, `WaterVarIn/OutTransferMod`, `add_to_output`. v4.5-style multi-level interface vs v5 `noahmp` derived-type pattern |
| `reference/contributing-pr.md` | Fork both repos, `git remote add` alias, push submodule first, request reviewer, sync fork with NCAR upstream |
| `reference/debugging.md` | Compile failures (jasper / netCDF), `create_forcing.exe` not built (OK in some configs), water balance violations, restart mismatches |

## Examples

| File | What it shows |
|------|---------------|
| `examples/PLAN_Texas_12p5km_NLDAS2_TACC.md` | A complete worked plan produced by `reference/designing-a-run.md` for the request "soil moisture/temp + LH, 3/6-hourly, any year, Texas, 12.5 km, on TACC" (matched-resolution case: grid = forcing, so no downscaling caveat) |
