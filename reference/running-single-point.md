# Running Noah-MP at a Single Point

Single-point (column) runs are the standard way to develop, debug, and
validate Noah-MP physics. One year at one site finishes in roughly a minute on
a login node.

Reference case used in the KW tutorials:
- **Bondville, IL** (cropland), 1998

Companion HRLDAS doc:
https://github.com/NCAR/hrldas/blob/master/hrldas/docs/README.single_point

---

## Step 1: Prepare the forcing

For built-in example sites, the HRLDAS distribution ships a pre-built forcing
under `HRLDAS_forcing/run/examples/single_point/`:

```
bondville.dat            ← raw single-point observations
create_point_data.f90    ← Fortran source for the converter
Makefile                 ← builds create_point_data.exe
```

`bondville.dat` has four sections:

1. **Location info**, lat/lon, land-use type, soil type, elevation
2. **Initial states**, soil moisture, soil temperature, SWE, skin temp, LAI
3. **Metadata**, land-use classification (`USGS` or `MODIS`)
4. **Conversion info**, units conversion factors per variable

The seven required forcing variables (per timestep, after the header) and
their expected units:

| # | Variable | Units |
|---|----------|-------|
| 1 | Wind speed | m s⁻¹ |
| 2 | Air temperature | K |
| 3 | Specific humidity | kg kg⁻¹ |
| 4 | Surface pressure | Pa |
| 5 | Downward shortwave radiation | W m⁻² |
| 6 | Downward longwave radiation | W m⁻² |
| 7 | Precipitation rate | mm s⁻¹ (= kg m⁻² s⁻¹) |

The "Conversion information" section of `bondville.dat` declares the
multiplicative factor used to map raw observation columns to these required
units, edit those factors when adapting `bondville.dat` to a new site
rather than pre-converting the data.

**Critical:** the forcing must be in **UTC**. `create_point_data.exe` does
not convert local time. If your site is in local time, convert it before
feeding `create_point_data.exe`.

Build and run the converter:

```bash
cd HRLDAS_forcing/run/examples/single_point
make
./create_point_data.exe
```

Output: 30-minute LDASIN files for the year covered by `bondville.dat`.

For other sites, edit a copy of `bondville.dat` with your station's metadata
and observations, then rerun `create_point_data.exe`.

---

## Step 2: Edit the namelist

The namelist lives in `hrldas/run/namelist.hrldas`. Sections you actually
edit:

### (1) Paths
```fortran
HRLDAS_SETUP_FILE = "../../HRLDAS_forcing/run/examples/single_point/HRLDAS_setup_..."
INDIR             = "../../HRLDAS_forcing/run/examples/single_point/LDASIN/"
OUTDIR            = "Out1D/"
```

### (2) Dates and run length
```fortran
START_YEAR  = 1998
START_MONTH = 1
START_DAY   = 2
START_HOUR  = 0
START_MIN   = 30
KDAY        = 365         ! run length in days
SPINUP_LOOPS = 0          ! repeat the same period N times for fast spinup
! RESTART_FILENAME_REQUESTED = "RESTART.YYYYMMDDHH_DOMAIN1"   ! uncomment to restart
```

### (3) Forcing variable names
Default values match the names `create_point_data.exe` writes, usually leave
alone.

### (4) Physics options
This is the multi-parameterization core of Noah-MP. Every option turns on a
different scheme:

```fortran
DYNAMIC_VEG_OPTION   = 4      ! 1-9: prescribed LAI vs dynamic vegetation
CANOPY_STOMATAL_RESISTANCE_OPTION = 1  ! 1=Ball-Berry, 2=Jarvis
BTR_OPTION           = 1      ! 1=Noah, 2=CLM, 3=SSiB
RUNOFF_OPTION        = 1      ! 1-8: BATS, TOPMODEL, MMF, VIC, XAJ, ...
SURFACE_DRAG_OPTION  = 1      ! 1=Most, 2=Chen97
FROZEN_SOIL_OPTION   = 1
SUPERCOOLED_WATER_OPTION = 1
RADIATIVE_TRANSFER_OPTION = 3
SNOW_ALBEDO_OPTION   = 1      ! 1=BATS, 2=CLASS, 3=SNICAR (v5.1+)
PCP_PARTITION_OPTION = 1
TBOT_OPTION          = 2
TEMP_TIME_SCHEME_OPTION = 3
GLACIER_OPTION       = 1
SURFACE_RESISTANCE_OPTION = 1
SOIL_DATA_OPTION     = 1
PEDOTRANSFER_OPTION  = 1
CROP_OPTION          = 0      ! 1 turns on crop model
IRRIGATION_OPTION    = 0
URBAN_OPTION         = 0
```

The full list of options and references is documented in
`run/README.namelist`. Always read that file for the version of HRLDAS you
have in hand, option numbers can drift between releases.

### (5) Timesteps
```fortran
FORCING_TIMESTEP    = 1800    ! seconds
NOAH_TIMESTEP       = 1800
OUTPUT_TIMESTEP     = 1800
SPLIT_OUTPUT_COUNT  = 1       ! 1 file per output step; 48 = daily files of 30-min steps
RESTART_FREQUENCY_HOURS = 24
```

`SPLIT_OUTPUT_COUNT = 48` with a 30-minute timestep packs each day into one
`YYYYMMDDHH.LDASOUT_DOMAIN1` file. `SPLIT_OUTPUT_COUNT = 1` writes one file
per output step (use only for very short runs).

---

## Step 3: Run

```bash
cd hrldas/hrldas/run
chmod +x hrldas.exe
./hrldas.exe
```

A 1-year single-point run finishes in roughly 1 minute on a login node. The
runtime log streams to stdout, redirect with `./hrldas.exe >& run.log` if
you want to grep it later.

---

## Step 4: Inspect output

```bash
module load ncview      # on HPC
ncview YYYYMMDDHH.LDASOUT_DOMAIN1
```

Common output variables to sanity-check first:
- `LH`, latent heat flux (W m⁻²), should track diel and seasonal cycle
- `HFX` (or `SH`), sensible heat flux (W m⁻²)
- `SOIL_M` (or `SoilMoisture`), soil moisture by layer
- `SOIL_T`, soil temperature by layer
- `BTRAN` / `SoilTranspFacAcc`, soil water transpiration factor (0-1)
- `RUNOFF` (`UGDRNOFF`, `SFCRNOFF`), runoff components

---

## Step 5: Run experiments outside the source tree

To avoid corrupting the source tree:

1. Keep all code edits and compilation in the source directory.
2. Create a per-experiment directory on a scratch filesystem (e.g.,
   `~/experiments/test_bondville_run01/`).
3. Copy `hrldas.exe`, all `*.TBL` files, the `HRLDAS_setup_*_d1`
   initial-state file (or the single-point forcing file containing the state
   section), and the LDASIN forcing into the experiment directory. Offline
   HRLDAS does **not** consume WRF's `wrfinput.nc`, initialization comes
   from `HRLDAS_setup` (2D) or the single-point forcing header.
4. Generate `namelist.hrldas` *inside* the experiment directory.
5. Submit jobs with unique log names so concurrent experiments don't
   overwrite each other.

This keeps `git status` clean and makes results reproducible.

---

## Common single-point pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| `cannot open ... LDASIN` | INDIR points to wrong location | Point to where `create_point_data.exe` wrote files |
| Output dates shifted | Forcing not in UTC | Convert before regenerating LDASIN |
| `LH` is zero year-round | `DYNAMIC_VEG_OPTION` mismatched with LAI input | For prescribed LAI use opt 1 or 4; for dynamic use 2/3/5/6 |
| Crash early in run | Restart file from a different physics config | Cold-start (comment out RESTART_FILENAME_REQUESTED) |

---

## Where to next

- Scale up to a CONUS 2D run: `running-2d-domain.md`
- Add a new output variable: `custom-output.md`
- Submit your changes upstream: `contributing-pr.md`
