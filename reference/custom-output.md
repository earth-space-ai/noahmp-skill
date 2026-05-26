# Adding a New Output Variable to Noah-MP

Many useful diagnostics are computed inside Noah-MP but never written to the
LDASOUT file. Adding one to the output is a recurring task. The procedure
differs significantly between v4.5 and v5+, the v5 refactor was largely
motivated by making this easier.

This guide covers two examples:

1. **`SoilTranspFacAcc` (v5 name) / `BTRAN` (v4.5 name)**, already a
   declared state variable; just needs to be wired through IO.
2. **`ThicknessCanBury`**, a *local* variable in `PhenologyMainMod.F90` that
   must first be promoted to the derived type before it can be output.

Tutorial source:
`KW-Mod-Tutorials/Noah-MP/Note3_Output_Additional_Variables.ipynb`

---

## v4.5 vs v5: why v5 is dramatically easier

In v4.5 the model is a single ~10k-line file (`module_sf_noahmplsm.F`). To
expose a local variable you had to:

1. Add `INTENT(OUT)` to the variable in `NOAHMP_SFLX`.
2. Thread it up through every parent subroutine's argument list.
3. Add an allocatable array in `module_sf_noahmpdrv.F`.
4. Call `add_to_output` in `IO_code/module_NoahMP_hrldas_driver.F`.

For variables defined inside nested subroutines, every level of the call
chain had to be edited. Easy to miss one and ship a broken build.

In v5, because every subroutine takes `noahmp` as its only argument and
accesses fields via `associate`, you only need to (a) declare the field once
in the right `*VarType.F90`, (b) `associate` it in the module that owns the
calculation, and (c) wire it through the HRLDAS IO transfer modules.

---

## Example 1: Add `BTRANXY` (= `SoilTranspFacAcc`) to LDASOUT

`SoilTranspFacAcc` is already a declared state variable in v5
(`noahmp%water%state%SoilTranspFacAcc`), so we only need to wire it through
the HRLDAS IO chain.

### Step 1, Declare the IO field

`noahmp/drivers/hrldas/NoahmpIOVarType.F90` (around L221):

```fortran
real(kind=kind_noahmp), allocatable, dimension(:,:) :: BTRANXY   ! soil transpiration factor (0-1)
```

### Step 2, Allocate and initialize

`noahmp/drivers/hrldas/NoahmpIOVarInitMod.F90`:

```fortran
! Allocate (around L183):
if ( .not. allocated(NoahmpIO%BTRANXY) ) &
   allocate( NoahmpIO%BTRANXY(XSTART:XEND, YSTART:YEND) )

! Initialize (around L601):
NoahmpIO%BTRANXY = 0.0
```

### Step 3, Transfer in (IO → 1D column model)

`noahmp/drivers/hrldas/WaterVarInTransferMod.F90` (around L77):

```fortran
noahmp%water%state%SoilTranspFacAcc = NoahmpIO%BTRANXY(I,J)
```

### Step 4, Transfer out (1D column model → IO)

`noahmp/drivers/hrldas/WaterVarOutTransferMod.F90` (around L128):

```fortran
NoahmpIO%BTRANXY(I,J) = noahmp%water%state%SoilTranspFacAcc
```

### Step 5, Add to the output list

`hrldas/IO_code/module_NoahMP_hrldas_driver.F`, inside the `add_to_output`
chain (around L1120):

```fortran
call add_to_output( NoahmpIO%BTRANXY, "BTRANXY", &
                    "Soil Transpiration Factor (0-1)", "-" )
```

### Step 6, Verify with `git diff`

```bash
cd noahmp && git diff drivers/
cd ../hrldas && git diff IO_code/
```

You should see exactly five small additions: declaration, allocation,
initialization, two transfers, and the `add_to_output` call.

### Step 7, Rebuild and check output

```bash
cd hrldas/hrldas
make clean && make >& compile.log
grep -i error compile.log    # empty
cd run
./hrldas.exe
ncview YYYYMMDDHH.LDASOUT_DOMAIN1   # BTRANXY now visible
```

---

## Example 2: Promote a local variable, then output it

`ThicknessCanBury` is locally defined inside `PhenologyMainMod.F90`:

```fortran
real(kind=kind_noahmp) :: ThicknessCanBury    ! thickness of canopy buried by snow [m]
```

To output it, we first promote it to a state variable of the energy domain.

### Step 1, Add to `EnergyVarType.F90`

Append to `type :: state_type` (next to similar diagnostics like
`RadSwBalanceError`):

```fortran
real(kind=kind_noahmp) :: ThicknessCanBury    ! thickness of canopy buried by snow [m]
```

### Step 2, Initialize in `EnergyVarInitMod.F90`

```fortran
noahmp%energy%state%ThicknessCanBury = 0.0
```

### Step 3, Replace local with `associate` in `PhenologyMainMod.F90`

Delete the original local declaration. In the existing `associate` block,
add `ThicknessCanBury => noahmp%energy%state%ThicknessCanBury`. The
calculation code stays unchanged.

### Step 4, Wire IO (same five steps as Example 1)

Then in the HRLDAS layer:

`NoahmpIOVarType.F90` (around L222):
```fortran
real(kind=kind_noahmp), allocatable, dimension(:,:) :: DBXY    ! thickness of canopy buried by snow (m)
```

`NoahmpIOVarInitMod.F90`:
```fortran
if ( .not. allocated(NoahmpIO%DBXY) ) &
   allocate( NoahmpIO%DBXY(XSTART:XEND, YSTART:YEND) )

NoahmpIO%DBXY = undefined_real
```

`drivers/hrldas/EnergyVarInTransferMod.F90` (around L58):
```fortran
noahmp%energy%state%ThicknessCanBury = NoahmpIO%DBXY(I,J)
```

`drivers/hrldas/EnergyVarOutTransferMod.F90` (around L115):
```fortran
NoahmpIO%DBXY(I,J) = noahmp%energy%state%ThicknessCanBury
```

`hrldas/IO_code/module_NoahMP_hrldas_driver.F`:
```fortran
call add_to_output( NoahmpIO%DBXY, "DB", &
                    "Thickness of Canopy buried by snow", "m" )
```

### Step 5, Rebuild and run

```bash
cd hrldas/hrldas && make clean && make
cd run && ./hrldas.exe
ncview YYYYMMDDHH.LDASOUT_DOMAIN1    # DB visible
```

---

## Naming conventions

- **HRLDAS IO variables** keep the legacy uppercase short names (`BTRANXY`,
  `DBXY`) for compatibility with downstream WRF / WRF-Hydro consumers.
- **`noahmp_type` fields** use descriptive long names with the
  subject-property convention (`SoilTranspFacAcc`, `ThicknessCanBury`).
- The mapping happens in the HRLDAS transfer modules, that's why those files
  exist.

---

## Pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| Compile error: `BTRANXY` not declared | Declared in one of the IO files but not in `NoahmpIOVarType` | Add the declaration to `NoahmpIOVarType.F90` first |
| Field is all `undefined_real` in output | `Out` transfer missing | Add `NoahmpIO%X(I,J) = noahmp%...` in the `*OutTransferMod.F90` |
| Field is all zero (or initial value) in output | `In` transfer missing → field never gets the v5 model's update | Add `noahmp%... = NoahmpIO%X(I,J)` in the `*InTransferMod.F90` |
| Compiles but `add_to_output` line is silently inactive | Conditional flag turned off | Check the surrounding `if ( noahmp_output_to_file )` guard |
| Restart works but mid-run output missing | Variable wired for restart but not output | `add_to_output` is separate from restart wiring |

---

## Where to next

- Submit your new output as a PR: `contributing-pr.md`
- Diagnose missing-output / wrong-value problems: `debugging.md`
