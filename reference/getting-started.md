# Getting Started with Noah-MP

This guide walks from zero to a built `hrldas.exe` with the `noahmp`
submodule. After this, see `running-single-point.md` to launch a real
simulation.

---

> **On TACC Lonestar6?** Hand the whole onboarding to Claude:
> `reference/setup-tacc.md` is an AI-native playbook where Claude opens
> the SSH session, runs `examples/test_tacc_deps.sh --clone`, auto-fixes
> missing modules, patches `user_build_options`, and drives `./configure`
> + `make` end-to-end. You only gate the irreversible decisions
> (credentials, allocation, configure choice, sign-off). Come back here
> for the cross-platform background.

## Step 1: Understand the two repositories

Noah-MP physics lives in **`NCAR/noahmp`**. To run it offline (without WRF /
MPAS / LIS / UFS), you need a driver. The default offline driver is
**`NCAR/hrldas`** (High-Resolution Land Data Assimilation System), which
embeds `noahmp` as a git submodule.

| Repo | What it is | URL |
|------|-----------|-----|
| `NCAR/hrldas` | Offline driver: I/O, forcing pre-processor, run scripts | https://github.com/NCAR/hrldas |
| `NCAR/noahmp` | Physics source code (refactored v5+) | https://github.com/NCAR/noahmp |

Branches in `NCAR/noahmp`:
- **`master`**, most stable, current released version (5.2.x as of late 2024)
- **`develop`**, active development; bug fixes and new physics options merged here continuously
- **`release-v4.5-WRF`**, same physics as v5.0 but old (monolithic) code structure
- Other version branches store historical releases

---

## Step 2: Clone with submodules

```bash
git clone --recurse-submodules https://github.com/NCAR/hrldas
cd hrldas
ls
# → expects: hrldas/  noahmp/  README.md
ls noahmp/src | head
# → expects ~136 *.F90 files including NoahmpMainMod.F90
```

If you forgot `--recurse-submodules`, the `noahmp/` directory will be empty.
Recover with:

```bash
git submodule update --init --recursive
```

---

## Step 3: Install prerequisites

Two third-party libraries are required to build HRLDAS+Noah-MP:

### netCDF (and its Fortran bindings)

Stores forcing, restart, and output files.

- **macOS:** `brew install netcdf netcdf-fortran`
- **Ubuntu/Debian:** `sudo apt-get install libnetcdf-dev libnetcdff-dev`
- **NCAR HPC (Derecho/Casper):** `module load netcdf` (loaded by default in many environments)
- **TACC (Lonestar6, Stampede3):** `module load netcdf`

### Jasper (jpeg2000)

Required by the GRIB reader inside `create_forcing.exe`.

- **macOS:** `brew install jasper`
- **Ubuntu/Debian:** `sudo apt-get install libjasper-dev`
- **From source:** see https://www2.mmm.ucar.edu/wrf/OnLineTutorial/compilation_tutorial.php#STEP2

### Fortran compiler

A modern compiler with Fortran 2003 support:

- **gfortran** ≥ 9 (free)
- **ifort** / **ifx** (Intel), recommended for performance on Intel CPUs

### MPI (optional but recommended)

Only needed if you build the parallel version. NCAR/Derecho and TACC clusters
provide it via `module load openmpi` or the Intel MPI module.

---

## Step 4: Configure

```bash
cd hrldas/hrldas
./configure
```

You will be prompted to pick a compiler+parallelization combo:

```
1.  Linux PGI compiler serial
2.  Linux PGI compiler MPI
3.  Linux ifort compiler serial
4.  Linux ifort compiler MPI
5.  Linux gfortran compiler serial      ← NCAR/CISL: pick this
6.  Linux gfortran compiler MPI
```

Recommendations:
- **NCAR Derecho/Casper:** option 5 (gfortran serial) for tutorials, option 4 (ifort MPI) for production CONUS runs
- **TACC Lonestar6:** option 3 (ifort serial), `pgfortran` is unavailable on ls6
- **Local laptop:** option 5 (gfortran serial)

This generates `user_build_options` in the `hrldas/` directory.

---

## Step 5: Edit `user_build_options`

Open `user_build_options` and verify these four library paths point to your
actual installed locations:

```makefile
NETCDFMOD   = -I/path/to/netcdf/include
NETCDFLIB   = -L/path/to/netcdf/lib -lnetcdff -lnetcdf
LIBJASPER   = -L/path/to/jasper/lib -ljasper
INCJASPER   = -I/path/to/jasper/include
```

On HPC, `nc-config --includedir` and `nc-config --libdir` print the correct
paths.

`F90FLAGS` defaults to `-O0` (no optimization) for debugging. For production
runs change to `-O3`. Do **not** mix optimization levels across rebuilds
without `make clean`.

For active debugging (segfaults, array bounds violations, NaN propagation),
add the runtime check flags appropriate to your compiler:

| Compiler | Recommended debug flags |
|----------|------------------------|
| gfortran | `-O0 -g -fcheck=all -fbacktrace -ffpe-trap=invalid,zero,overflow` |
| ifort / ifx | `-O0 -g -check all -traceback -fpe0` |

Append these to `F90FLAGS` in `user_build_options`, then `make clean &&
make`. Strip them again before production, `-fcheck=all` is roughly
2-5× slower.

---

## Step 6: Compile

```bash
make clean
make >& compile.log
```

Compile time: about 1-3 minutes on a modern laptop / login node.

Verify success:

```bash
grep -i error compile.log    # should print nothing
ls run/hrldas.exe            # should exist
ls HRLDAS_forcing/create_forcing.exe   # should exist (NLDAS pre-processor)
```

If only `hrldas.exe` is built and `create_forcing.exe` is missing, the
top-level `make` did not descend into the forcing pre-processor. Most
configurations require building it explicitly:

```bash
cd ../HRLDAS_forcing
make
ls create_forcing.exe    # should exist
```

You can still run single-point cases without `create_forcing.exe` (which is
needed only for the NLDAS-2 / 2D workflow).

The `run/` directory now contains:

```
hrldas.exe
namelist.hrldas
NoahmpTable.TBL    ← unified parameter table since v5.0
URBPARM.TBL · URBPARM_LCZ.TBL · URBPARM_UZE.TBL
GENPARM.TBL · SOILPARM.TBL · MPTABLE.TBL  (legacy, still loaded)
README.namelist
```

---

## Step 7: Smoke test

```bash
cd run
./hrldas.exe
```

If a default `namelist.hrldas` ships with a working forcing path, this prints a
banner and starts iterating. If it errors with `cannot open ... LDASIN`, you
need to point `INDIR` and `OUTDIR` in the namelist to a real forcing
directory, proceed to `running-single-point.md`.

---

## Common install pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| `noahmp/` directory empty | Forgot `--recurse-submodules` | `git submodule update --init --recursive` |
| `cannot find -lnetcdff` | netCDF Fortran binding not installed | Install `netcdf-fortran` (separate from C library) |
| `cannot find -ljasper` | Jasper missing or path wrong | Install jasper, fix `LIBJASPER` |
| `Symbol not found: __netcdf_MOD_*` | Compiler/lib mismatch (e.g. ifort lib + gfortran build) | Rebuild netCDF with same compiler, or pick matching `module load` |
| `make` succeeds, `hrldas.exe` missing | Earlier silent error in submodule build | `make clean && make >& compile.log`, search log for first error |

For ongoing FAQs, see https://github.com/NCAR/hrldas/discussions/72.

---

## Where to next

- One site, one year: `running-single-point.md`
- CONUS-scale 2D simulation: `running-2d-domain.md`
- Add a new output variable: `custom-output.md`
