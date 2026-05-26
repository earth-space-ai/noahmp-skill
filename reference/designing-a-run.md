# Designing a Noah-MP Run From a User Request

The other reference docs assume you already know *what* to run (a single point,
or CONUS NLDAS-2). This doc covers the step before that: a user hands you an
underspecified request like

> "Soil moisture, soil temp, and latent heat at 3 or 6 hour steps, any year,
> Texas, 12.5 km, on TACC."

and you have to turn it into a fully scoped, runnable plan. Most such requests
are **basic** (offline HRLDAS regional run) but **underspecified**: they name
the outputs and a region but omit the parameters that actually determine the
run. Your job is to elicit the missing pieces, apply sensible defaults, surface
the one or two genuine tradeoffs, and emit a plan doc.

This is a **design-time** doc. It produces a plan, not a simulation. Once the
plan is agreed, hand off to `getting-started.md` (build), `running-2d-domain.md`
(forcing + execution), and `custom-output.md` (if a requested variable is not in
the default output).

---

## Step 0: Classify the request

Almost every "give me Noah-MP data for <region> <resolution> <variables>"
request is an **offline HRLDAS 2D regional run**. Confirm that before anything
else, because it routes everything downstream:

| If the user wants... | Driver | Route to |
|----------------------|--------|----------|
| Gridded output over a region, forced by a reanalysis (NLDAS-2, etc.) | HRLDAS offline | this doc → `running-2d-domain.md` |
| One tower/site time series | HRLDAS offline, single point | `running-single-point.md` |
| Land states coupled to a running atmosphere | WRF / MPAS / LIS driver | out of scope for this skill |

If the request says "simulation data over a region for a year," it is offline
HRLDAS. Do not assume coupled WRF unless the user says so.

---

## Step 1: The seven parameters every offline run needs

A request is runnable only when all seven are pinned. Walk the list, fill what
the user gave, default the rest, and flag the ones that need a real decision.

| # | Parameter | Namelist / tool field | Default if unspecified | Notes |
|---|-----------|----------------------|------------------------|-------|
| 1 | **Output variables** | `add_to_output` + `NOAHMP_OUTPUT` | standard LDASOUT set | Check each requested var is in the default output (Step 4). |
| 2 | **Output cadence** | `OUTPUT_TIMESTEP` (s) | request-driven | 3 h = 10800, 6 h = 21600. |
| 3 | **Region / domain** | `geo_em` file (WPS) + `XSTART/XEND/YSTART/YEND` | none — must ask for a bounding box | Drives grid size and cost (Step 2). |
| 4 | **Resolution** | `geo_em` grid spacing | request-driven | At ≤ forcing resolution this is "real"; finer than forcing is a downscaling caveat (Step 3). |
| 5 | **Forcing dataset** | `create_forcing.exe` + `namelist.input.NLDAS` | NLDAS-2 over CONUS | Determines available years, grid, and prep tool (Step 3). |
| 6 | **Time period + spin-up** | `START_*`, `KHOUR`/`KDAY`, `SPINUP_LOOPS` | one full year + spin-up | "Any year" is a constraint, not freedom (Step 5). |
| 7 | **HPC target** | batch script + `./configure` option | ask: which TACC system + allocation | TACC = Frontera / Stampede3 / Lonestar6, Intel `ifort`/`ifx`, launch with `ibrun` (see `getting-started.md` Step 4, and Step 11 below). |

Only ask the user about parameters that are (a) missing AND (b) have no safe
default: in practice that is the **bounding box**, the **forcing dataset** (if
the region is outside CONUS, NLDAS-2 does not apply), the **specific year**, and
the **TACC system + allocation**. Everything else gets a stated default.

---

## Step 2: Size the domain before committing

Grid cell count is the single biggest cost driver and the easiest surprise.
Estimate it as soon as you have a bounding box and resolution:

```
ncols ≈ (lon_extent_km / dx_km)
nrows ≈ (lat_extent_km / dx_km)
cells ≈ ncols × nrows
```

Worked example (Texas, 12.5 km): ~1200 km E-W × ~1180 km N-S at 12.5 km ≈
**~9,000 cells**. Multiply mentally by the spin-up cycle count (Step 5) to get
the true work. State this number in the plan so the user is not surprised. At
this scale the job is small (node-minutes), so the bounding box barely affects
cost; still state the cell count so scale is explicit. Cell count scales as
1/dx², so a finer grid raises cost sharply — flag that if a user asks for one.

At runtime, `XSTART/XEND/YSTART/YEND` in `namelist.hrldas` can subset a larger
`geo_em` without regenerating it.

---

## Step 2b: Estimate the budget, and ALWAYS smoke test before the full run

Never submit the full multi-year, full-domain job blind. The design plan must
include a budget estimate, and the execution must include a short smoke test
that *measures* the per-step cost so the full-run estimate is grounded in real
numbers from the target machine, not a guess.

### Compute budget (a priori estimate)

```
total_model_steps = (KHOUR × 3600 / NOAH_TIMESTEP) × (1 + SPINUP_LOOPS)
core_seconds      ≈ cells × total_model_steps × per_cell_step_cost
node_hours        ≈ core_seconds / (cores_per_node × 3600)
```

`per_cell_step_cost` is machine/compiler dependent and not worth guessing — get
it from the smoke test below. Note the spin-up multiplier: with
`SPINUP_LOOPS = 8`, you pay ~9× the single-year cost.

### Storage budget — estimate a priori, then PIN it with the smoke test

LDASOUT volume is easy to under-estimate and can blow a `$SCRATCH` quota. Use
two numbers: a quick a-priori bound for the plan, then the **measured** number
from the smoke test, which is the one you actually trust.

A priori (sanity bound only):

```
bytes ≈ cells × n_output_vars × (sim_seconds / OUTPUT_TIMESTEP) × 4 bytes
```

Worked example (Texas 12.5 km ≈ 9k cells, 1 production year, 3-hourly output,
~30 default 2D LDASOUT fields, soil fields × 4 layers):

```
steps_out ≈ 365 × 24 / 3 = 2920
bytes     ≈ 9.0e3 × ~40 × 2920 × 4 ≈ 4.2e9 ≈ ~4 GB (uncompressed)
```

The a-priori formula ignores netCDF headers, per-file overhead, compression, and
the exact field count — it is easily off by 2×. **Pin it with the smoke test:**

```
# from the smoke-test output directory:
bytes_one_file = size of one LDASOUT file (ls -l) for the smoke subdomain
bytes_per_cell_per_outstep = bytes_one_file / cells_in_smoke_subdomain
# scale to production:
prod_bytes = bytes_per_cell_per_outstep × cells_full_domain × outsteps_production
```

`outsteps_production = production_seconds / OUTPUT_TIMESTEP`. Add spin-up output
too if your build emits LDASOUT during spin-up cycles (verify; if it does,
deleting it is the norm). This measured `prod_bytes` is what you check against
quota.

Mitigations to state in the plan: confirm `$SCRATCH`/`$WORK` quota first; subset
the output variable list (if only soil moisture, soil temperature, and LH are
needed, that cuts the ~40-field volume by roughly an order of magnitude);
compress the output with netCDF deflate (`nccopy -d1` / `ncks -L1`) as a
post-processing step — do not assume HRLDAS writes compressed LDASOUT at runtime
unless you confirm it; and discard spin-up output (confirm whether the spin-up
cycles emit LDASOUT in your build and delete it if so, rather than assuming they
are silent).

### Smoke test (mandatory, before the full run)

1. Build, then run the provided single-point or a tiny 3-day CONUS slice exactly
   as in `getting-started.md` / `running-2d-domain.md` to confirm the executable
   and forcing pipeline are correct.
2. Run a **small but representative** slab of the real domain: a short window
   (e.g., 3-7 days) on a modest `XSTART/XEND/YSTART/YEND` subset, on the target
   TACC node type with the production compiler flags (`-O3`).
3. Measure three things and scale each to production:
   - **Compute**: wall time, cells in the slab, model steps run → back out
     `per_cell_step_cost` → scale by full cells × full steps × (1 + `SPINUP_LOOPS`).
   - **Storage**: one LDASOUT file size ÷ slab cells → `bytes_per_cell_per_outstep`
     → scale by full cells × production outsteps (see formula above).
   - **Memory/decomposition**: peak RAM per MPI rank, to size ranks-per-node so
     the full domain fits node memory.
4. Only then size the production SLURM request (nodes, walltime) and confirm the
   scaled storage fits quota. If the scaled estimate is surprising, revisit the
   bounding box, output cadence, or variable subset before committing.

Put the a-priori budget in the plan up front; put the smoke-test measurement and
the scaled production estimate in the execution sequence, before the production
submit. The scaled numbers, not the a-priori ones, gate the production job.

---

## Step 3: Match the model grid to the forcing grid

The clean default is **model grid = forcing grid**. With NLDAS-2 (~0.125°,
~12.5 km), a 12.5 km model grid uses the forcing at its native resolution: no
interpolation to a finer grid, no spatial downscaling, and **no resolution
caveat to disclaim**. Both the land-surface static fields and the meteorological
forcing are at ~12.5 km. This is the recommended setup and what the worked
example uses.

Only depart from it if the user explicitly needs a grid **finer than the
forcing**. That is a different, more involved job, and you must disclose what it
means: the land-surface static fields would be at the fine resolution, but the
*weather systems* (precip, wind, cloud/radiation) would still carry only the
forcing resolution. If a user asks for that, flag it and confirm before
planning, because the right answer is usually one of:

| User needs | Right move |
|------------|------------|
| Standard regional land-surface fields | Match the grid to the forcing (12.5 km with NLDAS-2). Default. |
| Genuinely finer *meteorology* (convective-scale precip) | NLDAS-2 is the wrong forcing; a finer-resolution product (e.g., AORC) and a different prep path are needed. |

Keep the design at matched resolution unless there is a stated reason not to.

---

## Step 4: Confirm the requested variables are actually output

Map each requested variable to its Noah-MP field and check it is in the standard
LDASOUT set before promising it. **Verify the exact netCDF variable string in an
actual LDASOUT file** (`ncdump -h <YYYYMMDDHH>.LDASOUT_DOMAIN1`) rather than
hardcoding a name from memory — the output string names are defined in the
HRLDAS driver and have varied across versions:

| User term | Noah-MP field (internal) | Typical LDASOUT string | In default output? |
|-----------|--------------------------|------------------------|--------------------|
| Soil moisture | `SMOIS` (total) / `SH2O` (liquid) | `SOIL_M` / `SOIL_W` (verify) | yes |
| Soil temperature | `TSLB` | `SOIL_T` (verify) | yes |
| Latent heat flux | `LH` | `LH` (verify) | yes |
| Sensible heat | `HFX` | `HFX` (verify) | yes |
| Ground heat flux | `GRDFLX` | `GRDFLX` (verify) | yes |

Internal Noah-MP names (`SMOIS`, `SH2O`, `TSLB`) are confirmed in
`noahmp/drivers/hrldas/NoahmpIOVarType.F90`; the LDASOUT *output* strings live in
the HRLDAS driver, so confirm them once from a real output file in the Phase E
smoke test and use the confirmed names in the deliverable.

If a requested variable is **not** in the default set (e.g., an internal
diagnostic like `BTRANXY`), it must be added through the IO transfer chain —
route to `custom-output.md` and note the extra step in the plan. Do not promise
a variable you have not confirmed is emitted.

---

## Step 5: Period and spin-up (where naive plans go wrong)

"Any year" sounds like freedom; it is actually a constraint plus a decision:

1. **Pick one concrete year** the forcing covers. NLDAS-2 spans 1979-present, so
   any recent full year works. Pick one (e.g., a non-extreme year) rather than
   leaving it open. Note NLDAS-2 has a processing lag of days-to-weeks, so the
   *current* calendar year is incomplete; pick a year that has fully closed.
2. **Spin-up is mandatory for the slow variables.** Soil moisture and soil
   temperature — exactly the headline outputs of most such requests — carry
   long memory. A cold start contaminates them for months to years, and deep
   layers (down to ~2 m) over semi-arid regions take *many* years to
   equilibrate. Do not ship cold-start soil states.
   - Mechanism A: `SPINUP_LOOPS = N` repeats the simulation window N times before
     production (cheapest with a single forcing year).
   - Mechanism B: an external restart loop — run a year, feed its `RESTART` file
     back via `RESTART_FILENAME_REQUESTED`, repeat. Use this to chain multiple
     distinct years or if `SPINUP_LOOPS` misbehaves in your build. When you point
     at a restart, set `SPINUP_LOOPS = 0` and make `START_YEAR/MONTH/DAY/HOUR`
     match the restart file's timestamp exactly.
   - **Use one mechanism, not both**: a non-zero `SPINUP_LOOPS` together with a
     restart file will re-loop on an already-equilibrated state.
   - **How much:** target ~5-10 equivalent years for a region with dry/deep
     soils, and **verify convergence** (compare deep-layer annual means between
     successive cycles) rather than trusting a fixed count.
3. Set `KHOUR` (or `KDAY`) to the production year length (8760 h, 8784 in a leap
   year). Keep only the production-year output; if your build emits LDASOUT
   during spin-up cycles (verify), discard it.

---

## Step 6: Timesteps

- `FORCING_TIMESTEP` = the forcing cadence (NLDAS-2 hourly = 3600).
- `NOAH_TIMESTEP` = the model integration step. Offline Noah-MP is a 1-D column
  model, so horizontal grid spacing imposes **no** stability constraint — `3600`
  (matching the forcing) is the standard offline choice and is what
  `running-2d-domain.md` uses. A shorter step (1800 s) is *optional*; use it only
  if you actually observe instability (rare offline) or want sub-hourly internal
  resolution. Do not shorten it reflexively because of grid size; it multiplies
  compute for no stability benefit.
- `OUTPUT_TIMESTEP` = the requested cadence (3 h = 10800, 6 h = 21600). It must
  be an integer multiple of `NOAH_TIMESTEP` (the namelist reader enforces this).

---

## Step 7: Emit the plan

A complete worked example of the output of this whole procedure is in
`examples/PLAN_Texas_12p5km_NLDAS2_TACC.md` (the "soil moisture/temp + LH, 12.5
km, any year, Texas, on TACC" request — the matched-resolution case where grid =
forcing, so the downscaling caveat below does not apply). Use it as the model for
what a finished plan looks like.

Produce a plan doc with these sections (this is the template the agent fills):

1. **Objective** — table mapping each requested field to its LDASOUT variable
   and units; cadence; resolution; forcing; HPC target; period.
2. **Resolution-vs-forcing caveat** — the Step 3 honesty statement, in full.
3. **Architecture** — HRLDAS is the top-level repo; `noahmp` is its submodule
   (`git clone --recurse-submodules https://github.com/NCAR/hrldas`). The
   runnable `hrldas.exe` and `create_forcing.exe` come from HRLDAS;
   physics lives in the `noahmp` submodule. Cite `getting-started.md`.
4. **Domain sizing** — bounding box + cell-count estimate (Step 2).
5. **Budget** — compute estimate (with the spin-up multiplier) and storage
   estimate, plus the mandatory smoke-test-before-full-run note (Step 2b).
6. **Period + spin-up** — chosen year, spin-up mechanism and length, convergence
   check (Step 5).
7. **Step-by-step** — Build (`getting-started.md`) → `geo_em` → forcing via
   `create_forcing.exe` (`running-2d-domain.md`) → **smoke test + budget
   scaling** → namelist → production batch submit → verify → package.
8. **Namelist template** — filled `namelist.hrldas` (see Step 8 below).
9. **Batch + delivery** — a SLURM script sized from the smoke test (Step 11) and
   the post-processing/packaging steps so the output is usable.
10. **Open items** — only the parameters that genuinely need the user: bounding
   box, year, cadence, TACC system + allocation, soil/land-use dataset choice
   (the Step 9 intake questions).
11. **Risks** — forcing prep correctness, HRLDAS/noahmp version pairing, the
   resolution caveat, spin-up neglect, compute + storage budget overrun.

---

## Step 8: Namelist template to fill

These names match `noahmp/drivers/hrldas/NoahmpReadNamelistMod.F90` (v5.2) as of
this writing. **Before finalizing a plan, re-verify against the actual built
checkout** — block names, valid physics-option names, the subset variables, spin-up
restart behavior, whether spin-up cycles emit output, and compression support all
live in the HRLDAS source/`README.namelist`, not in this skill. Treat the template
as a starting point to confirm, not gospel.

```fortran
&NOAHLSM_OFFLINE
  HRLDAS_SETUP_FILE = "<LDASIN>/HRLDAS_setup_<YYYYMMDDHH>_d1"
  INDIR             = "<LDASIN>/"
  OUTDIR            = "<LDASOUT>/"

  START_YEAR  = <YYYY>
  START_MONTH = 1
  START_DAY   = 1
  START_HOUR  = 0
  START_MIN   = 0
  KHOUR       = 8760            ! 8784 if leap year

  NSOIL            = 4
  soil_thick_input = 0.10, 0.30, 0.60, 1.00

  FORCING_TIMESTEP = 3600       ! NLDAS-2 hourly
  NOAH_TIMESTEP    = 3600       ! standard offline; shorten only if needed (column model, no CFL)
  OUTPUT_TIMESTEP  = 10800      ! 3-hourly (21600 for 6-hourly)

  NOAHMP_OUTPUT           = 0   ! standard LDASOUT (SOIL_M, SOIL_T, LH included)
  RESTART_FREQUENCY_HOURS = 24
  ! Spin-up: use ONE mechanism, not both.
  ! Mechanism A (native loops): SPINUP_LOOPS > 0 AND RESTART_FILENAME_REQUESTED blank.
  ! Mechanism B (external restart): SPINUP_LOOPS = 0 AND point at a restart whose
  !   timestamp matches START_* below.
  RESTART_FILENAME_REQUESTED = " "   ! blank when SPINUP_LOOPS > 0
  SPINUP_LOOPS = 8                   ! ~5-10 equiv years; set 0 if using a restart

  ! optional runtime subset of a larger geo_em:
  ! XSTART = 1
  ! XEND   = 0
  ! YSTART = 1
  ! YEND   = 0
/
```

Physics options: use the standard recommended set as in `running-single-point.md`
unless the user has a reason to vary them.

---

## Step 9: The intake questions to actually ask

When the request is missing must-have parameters, ask only these (everything else
is defaulted). Keep it short; do not turn it into a 30-field form.

1. **Exact region bounds** — "Full state with a margin, or a specific lat/lon
   box? Land only, or include coast/neighboring areas?" (drives grid size/cost).
2. **Forcing + year** — "NLDAS-2 (CONUS, ~12.5 km) OK? Which single year (it must
   be a closed past year)?" If the region is outside CONUS, NLDAS-2 does not
   apply — see Step 10.
3. **Output cadence + variables** — confirm 3 h vs 6 h, and that the requested
   fields are in the default LDASOUT set (Step 4).
4. **HPC** — "Which TACC system (Frontera / Stampede3 / Lonestar6) and which
   allocation? Should I include the build, or is `hrldas.exe` already built?"
5. **Spin-up tolerance** — "Soil states need multi-year spin-up; is a ~5-10 year
   spin-up acceptable, or is there a constraint?" (only if cost is a concern).

If the user cannot answer the region or year, you cannot produce a runnable
plan — say so rather than guessing.

---

## Step 10: When NLDAS-2 is the wrong forcing

NLDAS-2 is CONUS-only (25-53 N, 125-67 W) and ~12.5 km. If the request needs
something it cannot provide, flag the alternative instead of forcing NLDAS-2:

| Need | Forcing to use | Note |
|------|----------------|------|
| Region outside CONUS | ERA5 / GLDAS / regional reanalysis | Different prep path; `create_forcing.exe` supports several sources, check its namelist. |
| True sub-12.5 km *meteorology* | AORC (~800 m, CONUS) or a convection-permitting WRF downscale | Real fine-scale precip/wind, not just terrain-driven thermodynamics. |
| Pre-1979 period | A reanalysis that extends earlier (e.g., ERA5 back to 1940) | NLDAS-2 starts 1979. |
| Operational/near-real-time | NLDAS-2 has a days-to-weeks lag | Use a faster-latency product if the user needs recent dates. |

State the substitution and its cost (different prep, different grid) in the plan.

---

## Step 11: Batch script and post-processing (so the deliverable is usable)

A plan is not done at "the model ran." Include these so the user gets data they
can use, not a directory of raw LDASOUT.

**Build the right binary**: pick serial vs MPI from the domain size measured in
the smoke test, not by default. A small matched-resolution domain (e.g., Texas at
12.5 km, ~9k cells) runs fine serially or on a single node. Reach for the MPI
`./configure` option (domain-decomposed across nodes) only when the cell count
and memory genuinely need it; do not assume "regional = MPI."

**SLURM template (TACC), sized from the smoke test (Step 2b).** This is the MPI
form; for a small domain that ran fine serially, drop `-n`/`impi`/`ibrun` and
just call `./hrldas.exe` on a single node.

```bash
#!/bin/bash
#SBATCH -J noahmp_run
#SBATCH -p <queue>             # e.g. normal (Stampede3/Frontera)
#SBATCH -N <nodes>             # from smoke-test scaling (often 1 at matched res)
#SBATCH -n <total_mpi_ranks>   # MPI only; ranks = nodes x ranks_per_node (mem-limited)
#SBATCH -t <HH:MM:SS>          # from smoke-test wall-time scaling x safety margin
#SBATCH -A <allocation>
#SBATCH -o noahmp_%j.out

module load intel impi netcdf    # match the build toolchain (drop impi if serial)
cd $SCRATCH/noahmp_run/run
ibrun ./hrldas.exe               # MPI build: TACC's launcher (not mpirun).
                                 # Serial build: just `./hrldas.exe`
```

If MPI, use `ibrun` on TACC, not `mpirun`/`mpiexec`. Size `-N`/`-n`/`-t` from the
smoke-test measurements, never guessed.

**Post-processing / delivery:**
- Subset to the requested variables to shrink the deliverable:
  `ncks -v SOIL_M,SOIL_T,LH in.LDASOUT out.nc` (verify names first with
  `ncdump -h`).
- Concatenate per-timestep LDASOUT files into one time series per variable with
  NCO (`ncrcat`) for easier downstream use.
- Compress: `nccopy -d1` (deflate) or `ncks -L1`.
- Provide a small README with the run's metadata (Step 7, section 9 of the plan
  template) so the data is self-describing.

---

## Checklist before declaring the plan done

- [ ] All seven Step-1 parameters are pinned (defaulted or asked, never silently
      omitted).
- [ ] Each requested output variable confirmed in the default set, or routed to
      `custom-output.md`.
- [ ] Cell-count estimate stated.
- [ ] Compute budget (with spin-up multiplier) and storage estimate stated.
- [ ] Smoke-test-before-full-run step is in the execution sequence, with the
      full-run estimate scaled from measured smoke-test numbers.
- [ ] Resolution-vs-forcing caveat stated honestly when grid is finer than
      forcing.
- [ ] Spin-up mechanism, length, and convergence check specified.
- [ ] `NOAH_TIMESTEP` set sensibly (3600 standard offline; not shortened reflexively for grid size); `OUTPUT_TIMESTEP` a multiple of it.
- [ ] HPC target named with its `./configure` option (TACC → Intel `ifort`/`ifx`),
      serial vs MPI decided from domain size, and a SLURM script sketched (MPI
      uses `ibrun`; serial calls `./hrldas.exe` directly).
- [ ] Post-processing/delivery (variable subset, concat, compress, README) is in
      the plan, not just "the model ran."
- [ ] Open items list contains only user-only decisions.
