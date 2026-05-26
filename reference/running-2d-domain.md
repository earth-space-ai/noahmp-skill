# Running Noah-MP on a 2D Regional Domain (CONUS NLDAS-2)

Once a single-point run works, the next step is a 2D regional simulation. The
canonical example is **CONUS at 0.125°** driven by **NLDAS-2 hourly forcing**.

Companion HRLDAS doc:
https://github.com/NCAR/hrldas/blob/master/hrldas/docs/README.NLDAS

---

## Step 1: Get a domain file (geo_em)

`create_forcing.exe` needs a `geo_em` NetCDF file with terrain height, land
mask, and land-use index for every grid cell. For NLDAS-2 the tutorial
distribution provides:

```
geo_em.d01_NLDAS0125.nc
```

For other domains, generate one with WRF Preprocessing System (WPS)
`geogrid.exe`:
https://www2.mmm.ucar.edu/wrf/OnLineTutorial/Basics/index.php

Quick view:

```bash
ncview geo_em.d01_NLDAS0125.nc      # variable: HGT_M for terrain height
```

---

## Step 2: Download NLDAS-2 forcing (NASA Earthdata)

NLDAS-2 lives at:
https://disc.gsfc.nasa.gov/datasets/NLDAS_FORA0125_H_002/summary?keywords=NLDAS

- Spatial resolution: 0.125° × 0.125° CONUS
- Temporal resolution: hourly
- Format: GRIB
- Coverage: 1979-01-01 to present

You need a free NASA Earthdata login. Set up directory layout:

```bash
mkdir -p NLDAS_forcing/{raw,extracted}
cd NLDAS_forcing/raw
chmod 777 download.sh
./download.sh    # prompts for Earthdata user/pass
```

A 3-day window downloads in about a minute.

---

## Step 3: Pre-process the GRIB files

Tools required: `wgrib` and `perl`.

### 3.1 Extract individual variables

```bash
cd hrldas/HRLDAS_forcing/run/examples/NLDAS/
```

Edit `extract_nldas.perl`:

```perl
@yrs = ("00");                  # year(s) to extract
$day_start = 1;
$day_end   = 3;                 # range within the year
$data_dir    = "/path/to/raw";
$results_dir = "/path/to/extracted";
```

Create the per-variable subdirectories the script expects:

```bash
cd /path/to/extracted
mkdir DLWRF DSWRF APCP PRES TMP SPFH UGRD VGRD INIT FIXED
```

Run:

```bash
perl extract_nldas.perl
```

### 3.2 (optional) Initial-state extraction

```bash
perl extract_nldas_init.perl
```

Pulls `TSOIL`, `SOILM`, `AVSFT`, `CNWAT`, `WEASD` for the chosen
initialization date into `INIT/`. Skip if you initialize from a WRF restart
or another LSM.

### 3.3 (optional) Drop the raw GRIB files

If disk-constrained, delete the raw GRIBs after extraction completes, they
are no longer needed.

### 3.4 Uncompress the elevation file

```bash
gzip -d run/examples/NLDAS/NLDAS_ELEVATION.grb.gz
```

This file is referenced by the `Zfile_template` field in
`namelist.input.NLDAS` (the `create_forcing.exe` namelist, not the run-time
`namelist.hrldas`). It supplies the NLDAS native elevation grid used to
height-adjust forcing variables (temperature, pressure) onto the target
domain. Set `Zfile_template = "NLDAS_ELEVATION.grb"` and place the
uncompressed file alongside it.

### 3.5 Build LDASIN with `create_forcing.exe`

```bash
cd hrldas/HRLDAS_forcing/
cp examples/NLDAS/namelist.input.NLDAS .
$EDITOR namelist.input.NLDAS    # set INPUTDIR, OUTPUTDIR, dates, geo_em path
./create_forcing.exe namelist.input.NLDAS
```

For NLDAS, the secondary shortwave and precipitation files are unused, set
them to the same paths as primary. A 3-day forcing dataset comes out around
167 MB.

```bash
ls /path/to/LDASIN/
# → LDASIN_DOMAIN1.YYYYMMDDHH.nc files + HRLDAS_setup_YYYYMMDDHH_d1
```

---

## Step 4: Edit `namelist.hrldas` for the 2D run

Switch the paths to the LDASIN directory you just produced:

```fortran
HRLDAS_SETUP_FILE = "../../../NLDAS_forcing/LDASIN/HRLDAS_setup_2000010100_d1"
INDIR             = "../../../NLDAS_forcing/LDASIN/"
OUTDIR            = "../../../NLDAS_forcing/LDASOU/"
```

Switch timesteps to hourly (NLDAS-2 is hourly):

```fortran
FORCING_TIMESTEP = 3600
NOAH_TIMESTEP    = 3600
OUTPUT_TIMESTEP  = 3600
```

Choose your physics options as for the single-point run.

---

## Step 5: Execute

For short runs (a few days at CONUS) the login node is fine, about 5 minutes
for 3 days at 0.125°:

```bash
./hrldas.exe
```

For longer runs, submit to a compute node. Example PBS script (`runhrldas.csh`)
on Cheyenne / Derecho:

```bash
#!/bin/csh
#PBS -N hrldas_conus
#PBS -A <project_code>
#PBS -l select=1:ncpus=128:mpiprocs=128
#PBS -l walltime=04:00:00
#PBS -q main
#PBS -j oe

cd $PBS_O_WORKDIR
mpiexec ./hrldas.exe
```

Submit with `qsub runhrldas.csh`.

---

## Step 6: Inspect output

```bash
ncview YYYYMMDDHH.LDASOUT_DOMAIN1
```

For animations across days, NCO + ImageMagick / Python (matplotlib +
cartopy + imageio) work well.

---

## Common 2D pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| `create_forcing.exe`: `wgrib not found` | wgrib not installed / not on PATH | `module load wgrib` or build from source |
| `INIT/` empty after extract | Wrong year/date in `extract_nldas_init.perl` | Match init date to first hour of run |
| Output land mask wrong | Used a geo_em from a different projection | Regenerate with WPS for your domain |
| `mpiexec` not picked up by `hrldas.exe` | Built serial via option 5 | Reconfigure with option 4 (ifort MPI) or 6 (gfortran MPI), `make clean && make` |
| All-zero precipitation | NLDAS APCP file missing or `extract_nldas.perl` skipped APCP | Re-run extraction with `APCP` directory present |

---

## Where to next

- Add a custom output variable to your CONUS run: `custom-output.md`
- Submit your changes upstream: `contributing-pr.md`
