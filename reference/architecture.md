# Noah-MP v5+ Architecture

The defining change of Noah-MP version 5.0 (March 2023) was a **modernization
refactor**: the monolithic ~10k-line `module_sf_noahmplsm.F` was decomposed
into 130+ focused `*Mod.F90` files communicating through a single
`noahmp_type` derived type. v5.0 has **identical physics to v4.5**, only the
code structure changed.

This page is the map you need before you edit anything.

---

## Top-level layout

```
noahmp/
├── src/                  ← all physics modules (this page)
├── drivers/
│   ├── hrldas/           ← HRLDAS coupling (IO transfer, namelist, table read)
│   ├── lis/              ← NASA Land Information System
│   ├── wrf/              ← WRF coupling
│   └── erf/              ← DOE ERF coupling
├── parameters/
│   ├── NoahmpTable.TBL   ← unified parameter file (replaces 3 legacy tables)
│   └── snicar_*.nc       ← SNICAR snow albedo lookup tables
├── docs/
│   ├── NoahMP_v5_technote.pdf
│   └── NoahMP_refactored_variable_name_glossary_Feb2023.xlsx
└── utility/
    ├── Machine.F90       ← defines `kind_noahmp`
    ├── ErrorHandleMod.F90
    ├── CheckNanMod.F90
    └── PiecewiseLinearInterp1dMod.F90
```

---

## The `noahmp_type` derived type

Every module receives a single argument of type `noahmp_type` and accesses
state, fluxes, parameters, and config through nested sub-types:

```fortran
type :: noahmp_type
  type(config_type)   :: config     ! grid, vegtype, soiltype, namelist options
  type(forcing_type)  :: forcing    ! atm forcing (T, q, p, SW, LW, precip, wind)
  type(energy_type)   :: energy     ! state + flux + param for energy
  type(water_type)    :: water      ! state + flux + param for water
  type(biochem_type)  :: biochem    ! state + flux + param for biogeochem
end type
```

Each domain sub-type has the same internal structure:

```fortran
type :: water_type
  type(state_type) :: state         ! prognostic + diagnostic state variables
  type(flux_type)  :: flux          ! per-timestep fluxes
  type(param_type) :: param         ! parameters from NoahmpTable.TBL
end type
```

The `*VarType.F90` files (e.g., `WaterVarType.F90`, `EnergyVarType.F90`)
declare these. The `*VarInitMod.F90` files (e.g., `WaterVarInitMod.F90`)
allocate and initialize them.

**Why this matters when editing:** to add a new state variable, you (1)
declare it in the appropriate `*VarType.F90`, (2) initialize it in the
matching `*VarInitMod.F90`, (3) `associate` it inside whichever `*Mod.F90`
needs to read or write it. You do **not** have to thread it through subroutine
argument lists like in v4.5. See `custom-output.md`.

---

## `kind_noahmp`

Defined in `noahmp/utility/Machine.F90`. By default this is `real(kind=4)`
(single precision). Every Noah-MP variable is declared
`real(kind=kind_noahmp)`, which means a single rebuild flag flips the entire
model between single and double precision.

```fortran
! In Machine.F90
integer, parameter :: kind_noahmp = 4    ! or 8 with -DDOUBLE_PREC
```

Most users leave `kind_noahmp = 4` and never recompile with
`-DDOUBLE_PREC`; the single-precision build is the standard production
configuration.

---

## The main driver call chain

`NoahmpMainMod.F90` is the per-column driver. Per timestep, for each grid
cell, it calls:

```
NoahmpMain
├── AtmosForcing            (downscale forcing)
├── PhenologyMain           (LAI/SAI/vegfrac)
├── PrecipitationHeatAdvect
├── EnergyMain              ← biggest block
│   ├── GroundRoughnessProperty
│   ├── PsychrometricVariable
│   ├── HumiditySaturation · VaporPressureSaturation
│   ├── SoilThermalProperty · SnowThermalProperty
│   ├── SurfaceAlbedo · SurfaceEmissivity
│   ├── CanopyRadiationTwoStream
│   ├── ResistanceAboveCanopy{Most,Chen97}
│   ├── ResistanceCanopyStomata{BallBerry,Jarvis}
│   ├── SurfaceEnergyFluxVegetated · SurfaceEnergyFluxBareGround
│   ├── SoilWaterTranspiration                ← BTRAN lives here
│   └── SoilSnowTemperatureMain
├── WaterMain
│   ├── CanopyHydrology · CanopyWaterIntercept
│   ├── SnowWaterMain (compaction, sublimation, snowpack hydrology)
│   ├── SoilWaterMain (infiltration, Richards' eq, transpiration extraction)
│   ├── GroundWater{TopModel,Mmf}
│   ├── Runoff{Surface,SubSurface}*
│   ├── TileDrainage*
│   └── WetlandWaterZhang22
├── BiochemNatureVegMain · BiochemCropMain
└── BalanceErrorCheck       ← water + energy conservation diagnostic
```

Glaciers go through a parallel chain (`*GlacierMod.F90`).

---

## Module families (by prefix)

| Prefix | Domain |
|--------|--------|
| `Atmos*` | atmospheric forcing |
| `BalanceErrorCheck*` | mass + energy conservation diagnostics |
| `Biochem*` · `CarbonFlux*` · `Crop*` | biogeochemistry, photosynthesis, crops |
| `CanopyHydrology` · `CanopyRadiation*` · `CanopyWaterIntercept` | canopy water + radiation |
| `Config*` | namelist + grid configuration |
| `ConstantDefineMod` | physical constants (one place) |
| `Energy*` · `Surface*` · `SoilSnowTemperature*` | energy budget |
| `Forcing*` | input forcing variables |
| `Glacier*` | glacier surface (parallel to vegetated/bare-ground chain) |
| `Ground*` · `Resistance*` | aerodynamic and surface resistances |
| `GroundWater*` · `WaterTable*` · `ShallowWaterTable*` | groundwater |
| `Irrigation*` | flood / micro / sprinkler irrigation |
| `MatrixSolverTriDiagonalMod` | implicit solver kernel |
| `Phenology*` | LAI/SAI dynamics |
| `Precipitation*` | rain/snow partition + heat advect |
| `Runoff*` | surface + subsurface runoff schemes |
| `Snow*` · `Snowpack*` · `SurfaceAlbedo*` | snow physics |
| `Soil*` | soil thermal + hydraulic properties, infiltration, transpiration |
| `Tile*` | tile drainage |
| `Wetland*` | wetland water (Zhang22) |
| `Water*` | water budget driver |

Knowing the prefix narrows your search to a handful of files.

---

## v4.5 → v5 variable renaming

v5 renamed many variables to be more self-describing. The authoritative
glossary is in
`noahmp/docs/NoahMP_refactored_variable_name_glossary_Feb2023.xlsx`. A few
common ones:

| v4.5 name | v5 name | v5 location |
|-----------|---------|-------------|
| `BTRAN` | `SoilTranspFacAcc` | `noahmp%water%state%SoilTranspFacAcc` |
| `BTRANI(IZ)` | `SoilTranspFac(IZ)` | `noahmp%water%state%SoilTranspFac` |
| `OPT_BTR` | `OptSoilWaterTranspiration` | `noahmp%config%nmlist%OptSoilWaterTranspiration` |
| `FCTR` (transpiration heat flux) | `Transpiration` | `noahmp%water%flux%Transpiration` |
| `SH2O` | `SoilLiqWater` | `noahmp%water%state%SoilLiqWater` |
| `SMC` | `SoilMoisture` | `noahmp%water%state%SoilMoisture` |
| `SICE` | `SoilIce` | `noahmp%water%state%SoilIce` |
| `STC` | `TemperatureSoilSnow` | `noahmp%energy%state%TemperatureSoilSnow` |

When porting an algorithm from v4.5 to v5, check the glossary first. The
naming is consistent: subject + property.

---

## Adding a new physics option

Pattern (matches SNICAR, MMF, wetland, snow-cover additions in v5.1):

1. Pick a namelist switch, extend `OptSoilWaterTranspiration`, `OptSnowAlbedo`, etc., or define a new one in `ConfigVarType.F90`.
2. Write a new `*Mod.F90` for the new physics. Take `noahmp` as the only argument. `associate` what you need.
3. Add a runtime guard at every call site:
   ```fortran
   if ( OptYourScheme == N ) then
      call YourScheme(noahmp)
   endif
   ```
4. Add new state/flux/param variables to the relevant `*VarType.F90` and initialize them in `*VarInitMod.F90`.
5. Add the new module to `Makefile` (object list + dependency line).
6. Add IO transfer in `drivers/hrldas/*Mod.F90` if the new state must persist across restarts or appear in output.
7. Read parameters from `NoahmpTable.TBL` via `drivers/hrldas/NoahmpReadTableMod.F90`.

The SNICAR addition (`OptSnowAlbedo == 3`) and the wetland scheme
(Zhang22) are the cleanest worked examples in v5.1+.
