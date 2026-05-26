<!--
EXAMPLE OUTPUT of the procedure in reference/designing-a-run.md.
This is the finished plan produced from the request: "soil moisture, soil temp,
and LH at 3/6-hourly, any year, Texas, 12.5 km, on TACC." Read it as a model for
what a completed design plan looks like; the paths/dates are illustrative.

Note: this is the matched-resolution case (model grid = forcing grid), so the
resolution-vs-forcing downscaling caveat does NOT apply. See Section 2.
-->

# Plan: Offline Noah-MP Simulation over Texas at 12.5 km, NLDAS-2 Forced, on TACC

Status: draft for student review
Date: 2026-05-26
Model: Noah-MP v5.2.0 + HRLDAS offline driver (HRLDAS embeds noahmp as a submodule)

## 1. Objective

Produce Noah-MP land-surface output for **Texas** with these deliverables:

| Field | Noah-MP field (internal) | LDASOUT string (verify) | Units |
|-------|--------------------------|-------------------------|-------|
| Soil moisture | `SMOIS` total / `SH2O` liquid | `SOIL_M` / `SOIL_W` | m3 m-3 |
| Soil temperature | `TSLB` | `SOIL_T` | K |
| Latent heat flux | `LH` | `LH` | W m-2 |

Internal names confirmed in `drivers/hrldas/NoahmpIOVarType.F90`. The LDASOUT
*output* variable strings are defined in the HRLDAS driver and have varied
across versions, so confirm the exact names once with `ncdump -h
<YYYYMMDDHH>.LDASOUT_DOMAIN1` in the smoke test (Section 5b) before using them in
the deliverable.

- Output cadence: **3-hourly or 6-hourly** (`OUTPUT_TIMESTEP = 10800` or `21600`).
- Model grid: **12.5 km** (0.125 deg), matching the NLDAS-2 forcing grid.
- Forcing: **NLDAS-2** (~0.125 deg, ~12.5 km).
- Compute: **TACC**.
- Time period: one full year (see Section 5 for picking it).

## 2. Resolution note: grid matches forcing, so no downscaling caveat

The model grid (12.5 km) **equals** the NLDAS-2 forcing grid (~0.125 deg). This
is the simplest, cleanest offline setup: the forcing is used at its native
resolution, with no interpolation to a finer grid and no spatial downscaling.

Consequently the "fine structure comes from the land surface, not the
atmosphere" caveat that applies to runs finer than the forcing **does not apply
here**. Both the land-surface static fields (land use, soil texture, terrain)
and the meteorological forcing are at ~12.5 km. The product is a faithful 12.5
km Noah-MP simulation; there is nothing to
disclaim about implied resolution.

The standard NLDAS-2 tutorial domain `geo_em.d01_NLDAS0125.nc` is already at
0.125 deg over CONUS, so the domain file is essentially off-the-shelf; you only
subset it to Texas (Section 4).

## 3. Architecture: what this repo is, and what else is needed

The `NCAR/noahmp` repo contains the **Noah-MP physics library AND the HRLDAS offline driver interface** under `drivers/hrldas/` (e.g., `NoahmpDriverMainMod.F90`, `NoahmpReadNamelistMod.F90`). What it does **not** contain is the build-options file, the top-level offline program glue, and the forcing/grid preprocessing tools: the driver `Makefile` includes `../../../hrldas/user_build_options`, and the repo README directs offline users to the **HRLDAS** repo (https://github.com/NCAR/hrldas) for the runnable system and its preprocessing utilities.

Practical reading of this: the offline build root is **HRLDAS**, which embeds this `noahmp` repo as a git submodule. Clone with `git clone --recurse-submodules https://github.com/NCAR/hrldas`; that pulls a matching `noahmp` into `hrldas/noahmp/`. `./configure` writes `user_build_options`, `make` produces `hrldas.exe` and `create_forcing.exe`. Do not assume an arbitrary HRLDAS commit pairs cleanly with this v5.2.0 `noahmp`; use the submodule-pinned pairing to avoid an interface-version conflict.

The offline workflow therefore has three external pieces beyond the physics/driver in this repo:

1. **HRLDAS build options + forcing/setup tools** (external, version-matched): `user_build_options` for TACC, plus utilities to prepare forcing and the setup file.
2. **The NLDAS-2 domain file** `geo_em.d01_NLDAS0125.nc` (0.125 deg CONUS), subset to Texas. `create_forcing.exe` converts it into the `HRLDAS_SETUP_FILE` (the `HRLDAS_setup_*_d1` file) alongside the forcing (Phase B/C).
3. **NLDAS-2 data**: downloaded from NASA GES DISC, then processed onto the 12.5 km grid in HRLDAS-readable NetCDF (no regridding to a finer grid).

Driver/namelist files this plan relies on (verified in repo):

| Component | Path |
|-----------|------|
| Offline driver main | `drivers/hrldas/NoahmpDriverMainMod.F90` |
| Namelist reader (authoritative var list) | `drivers/hrldas/NoahmpReadNamelistMod.F90` |
| Noah-MP source Makefile | `src/Makefile` |
| HRLDAS driver Makefile (expects `../../../hrldas/user_build_options`) | `drivers/hrldas/Makefile` |
| Parameter table | `parameters/NoahmpTable.TBL` |
| Tech note | `docs/NoahMP_v5_technote.pdf` |

## 4. Domain and grid sizing

Texas bounding box (full state, generous margin):
- Latitude: ~25.8 N to ~36.5 N
- Longitude: ~106.7 W to ~93.5 W

At 12.5 km (~0.125 deg):
- East-west extent ~1200 km, north-south ~1180 km.
- Grid: roughly **96 x 94 ≈ ~9,000 cells** (the exact extent comes from the
  Texas subset of `geo_em.d01_NLDAS0125.nc`; budget ~9k-12k cells).

This is a small domain by HPC standards: a 1-year hourly run over ~9k cells is
minutes-scale on a single node, and even a multi-year spin-up is modest. MPI is
optional at this size (serial may be entirely sufficient); confirm with the
smoke test (Section 5b). Confirm the exact bounding box with the student; a
tighter, land-only box trims a few cells but barely matters at this scale.

The model can be run over the full domain, or subset at runtime with
`XSTART/XEND/YSTART/YEND` in the namelist (present in `NoahmpReadNamelistMod.F90`).

## 5. Choosing the year and spin-up (this matters for the requested variables)

Soil moisture and soil temperature are **slow-memory** variables. A cold start contaminates them for months to years. The two requested state variables are exactly the ones spin-up protects. Plan:

- **Pick one analysis year**, e.g. **2018** (NLDAS-2 covers 1979-present, so any recent closed year works; 2018 is a reasonable non-extreme year over Texas). Final choice is the student's.
- **Spin-up**: run the year (or a multi-year lead-in) repeatedly until soil states stabilize. Two mechanisms:
  - `SPINUP_LOOPS = N` repeats the simulation window N times before the production run (native namelist variable in `NoahmpReadNamelistMod.F90` for v5.2.0; cheapest if using a single year), or
  - an **external restart loop**: run one year, rename the output `RESTART` file, point `RESTART_FILENAME_REQUESTED` at it, and repeat via a shell script. Use this if `SPINUP_LOOPS` behaves unexpectedly in the HRLDAS build, or to chain multiple distinct forcing years.
  - **How long**: 2 years is NOT enough. West Texas is semi-arid to arid (Chihuahuan Desert, High Plains), and the deep soil layers (down to 2.0 m) take many years to equilibrate from a cold start. Target **5-10 equivalent years** of spin-up, and verify convergence (Section 6, Phase F) rather than assuming a fixed count. Use one mechanism, not both: a non-zero `SPINUP_LOOPS` with a restart file re-loops an already-equilibrated state. State the choice in the writeup. At ~9k cells the spin-up is cheap, so erring long is fine.
- Keep only the analysis-year output. If the build emits LDASOUT during spin-up cycles (verify), delete it rather than assuming the cycles are silent.

## 5b. Budget estimate and mandatory smoke test

Even though this domain is small, estimate the budget and confirm with a short smoke test before the full multi-year run.

**Compute (a priori):**
```
total_model_steps = (KHOUR x 3600 / NOAH_TIMESTEP) x (1 + SPINUP_LOOPS)
                  = (8760 x 3600 / 3600) x (1 + 8) = 8760 x 9 = 78,840 steps
core_seconds     ~= cells x total_model_steps x per_cell_step_cost
```
With ~9k cells this is tiny; `per_cell_step_cost` from the smoke test confirms it. The ~9x spin-up multiplier still dominates the (small) total. Expect node-minutes, not node-hours.

**Storage:** estimate a priori, then pin it with the smoke test.

A priori bound:
```
bytes ~= cells x n_output_vars x (sim_seconds / OUTPUT_TIMESTEP) x 4
       ~= 9.0e3 x 40 x 2920 x 4 ~= 4.2e9 ~= ~4 GB uncompressed  (production year)
```
This ignores headers, per-file overhead, and compression, so it is easily 2x off. Pin it with the smoke test:
```
bytes_per_cell_per_outstep = (one smoke LDASOUT file size) / (cells in smoke subdomain)
prod_bytes = bytes_per_cell_per_outstep x cells_full_domain x (production_seconds / OUTPUT_TIMESTEP)
```
`prod_bytes` is the number checked against quota. At ~9k cells this is single-digit GB, well within any TACC quota. Mitigations are optional at this scale but cheap: subset the output to just soil moisture / soil temp / LH; compress as a post-processing step (`nccopy -d1` / `ncks -L1`) rather than assuming HRLDAS writes compressed LDASOUT at runtime; and discard spin-up-cycle output if the build emits it (verify).

**Smoke test (run BEFORE the production job, Phase D):**
1. Build, then run the provided single-point case and a tiny 3-day CONUS slice to confirm the executable + forcing pipeline.
2. Run a 3-7 day window on the (already small) Texas domain, on the target TACC node type with production flags (`-O3`).
3. Measure and scale each to production:
   - compute: wall time, cells, steps -> `per_cell_step_cost` -> x full cells x full steps x (1 + `SPINUP_LOOPS`);
   - storage: one LDASOUT file size / slab cells -> `bytes_per_cell_per_outstep` -> x full cells x production outsteps (formula above);
   - memory: peak RAM per rank (at ~9k cells, a single node is ample; decide serial vs MPI here).
4. Then size the production job (likely a single short node allocation) and confirm storage fits quota.

## 6. Step-by-step execution plan

### Phase A — Build on TACC
1. Choose TACC system (Frontera / Stampede3 / Lonestar6) and load the matching toolchain (Intel `ifort`/`ifx` + NetCDF/HDF5 + Jasper modules; Intel-MPI if building MPI). Record exact module versions.
2. Clone the offline system with submodules: `git clone --recurse-submodules https://github.com/NCAR/hrldas` (embeds the `noahmp` submodule). Run `./configure` and edit `user_build_options` for the NetCDF/Jasper paths (`nc-config`), `-O3`. See the skill's `getting-started.md`. A serial build is sufficient for this ~9k-cell domain; build MPI only if you prefer it.
3. `make clean && make`; confirm `run/hrldas.exe` and `HRLDAS_forcing/create_forcing.exe` both build.
4. Build smoke test: run the shipped single-point (Bondville) case to confirm the executable works before scaling up. (Domain/budget smoke test is Phase D.)

### Phase B — Domain file (HRLDAS_SETUP_FILE) at 12.5 km
5. Start from the NLDAS-2 tutorial domain `geo_em.d01_NLDAS0125.nc` (0.125 deg CONUS); subset it to the Texas bounding box, or regenerate a Texas-only 0.125 deg `geo_em.d01.nc` with WPS geogrid. Either way the grid spacing is 12.5 km, matching the forcing.
6. Static datasets at 12.5 km: MODIS land use (USGS categories work with default `NoahmpTable.TBL`), default soil texture (STATSGO). Confirm `SOIL_DATA_OPTION` matches the soil dataset.
7. `create_forcing.exe` converts the domain file into the HRLDAS setup file (`HRLDAS_setup_*_d1`) containing `XLAT, XLONG, HGT, MAPFAC_*, SHDMAX, SHDMIN, XLAND, IVGTYP, ISLTYP, DZS, ZS, TMN, SEAICE` (LAI optional).

### Phase C — Forcing (NLDAS-2 -> 12.5 km LDASIN via `create_forcing.exe`)

Use the HRLDAS forcing preprocessor (`create_forcing.exe`) on the 12.5 km grid. Because the grid matches NLDAS-2, the forcing is used at native resolution (no regridding to a finer grid). See HRLDAS `README.NLDAS` and the skill's `running-2d-domain.md`.

8. Download NLDAS-2 hourly forcing (NLDAS_FORA0125_H, GRIB) from NASA GES DISC for the analysis year (plus extra years only if you use the external multi-year restart-loop spin-up; the default `SPINUP_LOOPS = 8` re-uses the single analysis year). Requires a free Earthdata login. NLDAS-2 covers CONUS (25-53 N, 125-67 W), which fully contains Texas; coverage 1979-present (days-to-weeks lag, so use a closed past year).
9. Extract per-variable GRIB fields with `extract_nldas.perl` (creates `TMP, SPFH, UGRD, VGRD, PRES, DLWRF, DSWRF, APCP` subdirs). Uncompress `NLDAS_ELEVATION.grb.gz` and set `Zfile_template = "NLDAS_ELEVATION.grb"` in `namelist.input.NLDAS`. (Matched horizontal resolution removes the downscaling caveat; any residual height adjustment only matters if the setup-file terrain differs from `NLDAS_ELEVATION.grb`, so keep the standard config.)
10. Run `create_forcing.exe namelist.input.NLDAS` pointed at the Texas 12.5 km `geo_em` to produce hourly `LDASIN_DOMAIN1.YYYYMMDDHH.nc` plus the `HRLDAS_setup_YYYYMMDDHH_d1` initial-state file. This writes the forcing variable names Noah-MP expects (`T2D, Q2D, U2D, V2D, PSFC, LWDOWN, SWDOWN, RAINRATE`).
11. In the smoke test, confirm precipitation is non-zero and spatially sensible (a common failure is a missing `APCP` extraction) and that the fields cover the full Texas domain.
12. Timesteps: `FORCING_TIMESTEP = 3600` (NLDAS-2 hourly). `NOAH_TIMESTEP = 3600` is the standard offline choice (Noah-MP is a 1-D column model). `OUTPUT_TIMESTEP = 10800` (3 h) or `21600` (6 h).

### Phase D — Smoke test and budget scaling (BEFORE production)
13. Run the smoke test from Section 5b: a 3-7 day window on the Texas domain, on the target TACC node type with production flags. Measure wall time, cells, steps, output bytes.
14. Scale to the full period x (1 + `SPINUP_LOOPS`); confirm compute and storage (both small here). Decide serial vs single-node MPI.

### Phase E — Production run
15. Configure `namelist.hrldas` (template in Section 7).
16. Submit a short SLURM job (single node is ample at ~9k cells; MPI optional). The spin-up (~9x the year) dominates the (small) cost. Use `RESTART_FREQUENCY_HOURS` to checkpoint so jobs are resumable.
17. Run order: spin-up (output discarded) then the production year with `OUTPUT_TIMESTEP` set to 3 h or 6 h. Subset the output variable list to soil moisture / soil temp / LH if the full default set is not needed.

### Phase F — Verify and deliver
18. Confirm output files contain the soil-moisture/soil-temp/LH fields at the requested cadence; verify the exact LDASOUT variable strings with `ncdump -h` (Section 1) and use those names downstream. **Verify spin-up convergence**: compare deep-layer soil-moisture annual-mean fields between successive spin-up cycles and confirm the year-to-year change is below a small tolerance, especially over West Texas. If still drifting, add cycles (cheap at this scale).
19. Sanity-check against an independent reference (e.g., NLDAS-2 NOAH soil moisture climatology, or SMAP/ESA-CCI surface soil moisture pattern) for gross errors.
20. Package output + a short README describing domain (12.5 km, matching forcing), period, forcing, spin-up length and convergence evidence, physics options, and output variable names. No resolution caveat is needed (Section 2).

## 7. Namelist template (`namelist.hrldas`, NOAHLSM_OFFLINE block)

Variable names match `drivers/hrldas/NoahmpReadNamelistMod.F90` (v5.2.0); re-verify against the built HRLDAS checkout before finalizing.

```fortran
&NOAHLSM_OFFLINE
  HRLDAS_SETUP_FILE  = "./setup/HRLDAS_setup_2018010100_d1"  ! from create_forcing.exe, NOT raw geo_em
  INDIR              = "./forcing"        ! 12.5km NLDAS-2 hourly NetCDF
  OUTDIR             = "./output"

  START_YEAR  = 2018
  START_MONTH = 1
  START_DAY   = 1
  START_HOUR  = 0
  START_MIN   = 0
  KHOUR       = 8760                       ! 365-day production year (8784 if leap)

  NSOIL            = 4
  soil_thick_input = 0.10, 0.30, 0.60, 1.00

  FORCING_TIMESTEP = 3600                  ! NLDAS-2 hourly
  NOAH_TIMESTEP    = 3600                   ! standard offline
  OUTPUT_TIMESTEP  = 10800                 ! 3-hourly (use 21600 for 6-hourly)

  NOAHMP_OUTPUT           = 0              ! standard output set (includes SOIL_M, SOIL_T, LH)
  SKIP_FIRST_OUTPUT       = .false.
  RESTART_FREQUENCY_HOURS = 24
  ! Spin-up: use ONE mechanism. Native loops -> SPINUP_LOOPS>0 and restart blank.
  ! External restart -> SPINUP_LOOPS=0 and START_* must match the restart timestamp.
  RESTART_FILENAME_REQUESTED = " "         ! blank when SPINUP_LOOPS > 0
  SPINUP_LOOPS = 8                         ! ~5-10 equiv years (Phase F convergence check); 0 if using a restart

  ! grid subset (optional; defaults run full geogrid domain)
  ! XSTART = 1
  ! XEND   = 0
  ! YSTART = 1
  ! YEND   = 0
/

&NOAHMP_OFFLINE_PHYSICS
  ! Standard recommended physics; adjust only with reason.
  DYNAMIC_VEG_OPTION                = 4
  CANOPY_STOMATAL_RESISTANCE_OPTION = 1
  BTR_OPTION                        = 1
  SURFACE_RUNOFF_OPTION             = 3
  SUBSURFACE_RUNOFF_OPTION          = 3
  SURFACE_DRAG_OPTION               = 1
  SUPERCOOLED_WATER_OPTION          = 1
  FROZEN_SOIL_OPTION                = 1
  RADIATIVE_TRANSFER_OPTION         = 3
  SNOW_ALBEDO_OPTION                = 1
  PCP_PARTITION_OPTION              = 1
  TBOT_OPTION                       = 2
  TEMP_TIME_SCHEME_OPTION           = 1
  GLACIER_OPTION                    = 1
  SURFACE_RESISTANCE_OPTION         = 1
  SOIL_DATA_OPTION                  = 1
  PEDOTRANSFER_OPTION               = 1
  CROP_OPTION                       = 0
  IRRIGATION_OPTION                 = 0
/
```

Notes:
- The exact physics-block name/contents should be reconciled against the HRLDAS-provided example `namelist.hrldas`; option *names* above match the v5.2.0 reader, but HRLDAS owns the final namelist file layout.
- Soil moisture, soil temperature, and LH are part of the standard output set (`NOAHMP_OUTPUT = 0`); no special flag needed. Confirm the exact LDASOUT variable strings with `ncdump -h` (Section 1).

## 8. Open items needing the student's confirmation

1. **Exact Texas bounding box** (full state with margin, or land-only) — at 12.5 km this barely affects cost, so a generous box is fine.
2. **Analysis year** (default suggestion 2018) and **spin-up length** (`SPINUP_LOOPS` ~8, i.e. 5-10 equivalent years).
3. **Output cadence**: 3-hourly or 6-hourly (template defaults to 3-hourly).
4. **TACC system + allocation** (Frontera / Stampede3 / Lonestar6) and whether the build is in scope here.
5. **Soil/land-use datasets** (defaults: MODIS/USGS land use, STATSGO soil).

## 9. Risks

- **Forcing prep correctness**: `create_forcing.exe` handles the NLDAS-2 processing, but it is still where silent errors hide. Verify in the smoke test that precipitation is non-zero and spatially sensible (a common failure is a missing `APCP` extraction) and that fields cover the full Texas domain.
- **HRLDAS version pairing**: the offline system is built from a version-matched HRLDAS checkout that embeds the `noahmp` submodule (`git clone --recurse-submodules https://github.com/NCAR/hrldas`). A mismatched submodule commit can fail to build or wire the v5.2.0 interface incorrectly. Confirm the intended pairing; the build smoke test de-risks this early.
- **Spin-up neglect**: skipping or under-running it makes the headline variables (soil moisture/temperature) unreliable, especially deep layers over West Texas. Target 5-10 equivalent years and verify convergence; the run is cheap, so err long.
- **Over-engineering for scale**: at ~9k cells this is a small job. Do not reach for large multi-node MPI allocations or elaborate storage mitigations; a single short node allocation and a few GB of output are the realistic scope.
