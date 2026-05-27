# TACC ls6 dependency-test + setup guide for Noah-MP/HRLDAS

## Goal

Give a Noah-MP/HRLDAS user on TACC Lonestar6 a one-shot way to verify their
build dependencies, plus an interactive Claude-driven playbook that takes
them from a fresh ls6 login to a working `hrldas.exe`. Stop at successful
build; running the model is covered by the existing
`reference/running-single-point.md` and `reference/running-2d-domain.md`.

## Source

Distilled from `KW-Mod-Tutorials/Noah-MP/KW-PHS-Note0_Download_Compile.ipynb`
(terminal transcripts from ls6 sessions). Specifically:

- cell 14 — `which ifort/gfortran/pgfortran` probes
- cell 16 — rationale for picking `./configure` option 3 (ifort serial) on ls6
- cell 36 — canonical TACC `user_build_options` lives at
  `https://github.com/ktwu01/Ori_RPM/blob/main/hrldas_phs/hrldas/user_build_options_TACC`
- cell 51 — NCAR `Fortran_C_tests.tar` runner (TEST_1..4 + csh/perl/sh)
- cell 55 — known-good vs broken netCDF builds under `/opt/apps`

## Artifacts

### 1. `examples/test_tacc_deps.sh`

A self-contained bash script users run on ls6. Six probes, each prints
`[PASS] / [WARN] / [FAIL]` with a one-line remediation hint.

```
1. Host check        — confirm ls6.tacc.utexas.edu (WARN if not)
2. Compiler probe    — which {ifort, gfortran, gcc, cpp, pgfortran}
3. netCDF probe      — find /opt/apps -name netcdf.inc; flag known-good
                       ifort19 build vs the broken ones from cell 55
4. Jasper probe      — find libjasper; respect $TACC_JASPER_* if loaded
5. NCAR Fortran/C    — wget Fortran_C_tests.tar into ~/test_noahmp_deps;
                       compile + run TEST_1..4 + csh/perl/sh; assert SUCCESS
6. Summary           — print recommended ./configure choice (3 = ifort serial)
                       and a user_build_options stanza ready to paste
```

Exit 0 iff all six pass. No side effects outside `~/test_noahmp_deps/`. No
`module load` — the script reports what's missing and lets the user load
modules themselves.

### 2. `reference/setup-tacc.md`

A six-phase playbook Claude reads and executes step by step. Each phase
ends with a "STOP — ask user" marker so Claude can't sleepwalk past a
failure.

```
Phase 0  Pre-flight     — confirm host = ls6, $WORK/$SCRATCH visible, project
                          allocation present (`/usr/local/etc/taccinfo`)
Phase 1  Dep test       — run examples/test_tacc_deps.sh, parse output,
                          confirm or remediate
Phase 2  Clone repo     — git clone --recurse-submodules https://github.com/NCAR/hrldas
                          into $WORK (not $HOME); verify noahmp/ non-empty
Phase 3  Build options  — fetch ktwu01/Ori_RPM user_build_options_TACC as
                          a reference; confirm netCDF/Jasper paths from Phase 1
Phase 4  Configure      — ./configure; show menu, confirm option 3 with user
                          before sending the keystroke
Phase 5  Make           — make >& compile.log; tail; grep for "hrldas.exe"
Phase 6  Handoff        — point to running-single-point.md / designing-a-run.md;
                          remind about idev before any real run
```

### 3. Wiring

- One row added to the `SKILL.md` doc-map table for `reference/setup-tacc.md`.
- One bullet in `reference/getting-started.md` Step 1 pointing TACC users to
  the new playbook.
- The script lives under `examples/` next to `PLAN_Texas_12p5km_NLDAS2_TACC.md`
  so worked plan + setup tooling are co-located.

## Out of scope (YAGNI)

- Stampede3 / Frontera variants — source transcript is ls6-only.
- MPI build — ls6 transcript picked serial; MPI only relevant for prod CONUS.
- Auto `module load` — script reports, user loads.
- Running the model — already covered in `running-*.md`.

## Success criteria

1. `bash examples/test_tacc_deps.sh` on a clean ls6 login exits 0 and prints
   the recommended `./configure` choice plus a ready-to-paste
   `user_build_options` stanza.
2. A user with no prior Noah-MP experience can paste `setup-tacc.md` into a
   Claude session and reach a built `hrldas.exe` without ever leaving the
   guide.
3. `tsc --noEmit` equivalent for the repo: no broken doc links. The new doc
   is reachable from both `SKILL.md` and `reference/getting-started.md`.
