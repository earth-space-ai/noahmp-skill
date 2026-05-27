# Interactive setup on TACC Lonestar6

Take a user from a fresh ls6 login to a working `hrldas.exe`. Runs as a
**Claude-driven playbook**: each phase ends with a "**STOP — ask user**"
checkpoint so failures cannot sleepwalk past. End state is a built executable;
running the model is covered by `running-single-point.md` and `running-2d-domain.md`.

For why ls6 specifically: the source recipe was distilled from terminal
transcripts on ls6 (KW-Mod-Tutorials, `KW-PHS-Note0_Download_Compile.ipynb`).
Stampede3 / Frontera variants are out of scope here; most of the script is
portable but the netCDF path heuristics are ls6-tuned.

---

## How Claude should drive this

For each phase below:

1. Read the phase block. Run the listed commands one at a time (the user may
   need to read each output before the next runs).
2. Paste the user-visible output of decision-point commands back into the
   conversation so the user can confirm.
3. At the "**STOP — ask user**" line, do **not** continue until the user
   says go. If the check fails, follow the remediation hint, then re-run the
   check before advancing.
4. Never auto-`module load` on the user's behalf. Print the suggested module
   commands and let them run them — modules change the environment for the
   rest of their session.
5. The script in Phase 1 already encodes most "is this correct" logic. Trust
   its PASS/FAIL output; don't re-derive.

---

## Phase 0 — Pre-flight

Confirm the user is where they think they are.

```bash
hostname -f                                    # expect *.ls6.tacc.utexas.edu
echo "$WORK"   ; ls "$WORK"   2>/dev/null      # expect /work/<id>/<user>/ls6, populated
echo "$SCRATCH"; ls "$SCRATCH" 2>/dev/null     # expect /scratch/<id>/<user>, populated
test -f /usr/local/etc/taccinfo && cat /usr/local/etc/taccinfo  # project allocation summary
```

Why each line matters:

- **Host:** the rest of this guide assumes ls6 module names and `/opt/apps`
  paths. If they're on a compute node already (`c???-???`), pull them back to
  a login node for the dep test and build — compute nodes have no outbound
  network, so `wget` and `git clone` will hang.
- **`$WORK`:** clone the source here. `$HOME` on ls6 has a small quota and
  rejecting a recurse-submodule clone halfway through is a bad first
  experience.
- **`$SCRATCH`:** run outputs go here. Not used until later (running-the-model
  docs), but worth confirming the user has one and knows the purge policy.
- **`taccinfo`:** shows allocation balance. Cheap to check; expensive to
  discover at sbatch time.

**STOP — ask user:** "Is `$WORK` populated and is your project allocation
non-zero? If not, you're on the wrong machine or your account isn't set
up — fix before continuing."

---

## Phase 1 — Run the dependency test

```bash
cd ~                                                       # script's tarball lives in ~/test_noahmp_deps/
bash /path/to/noahmp-skill-public/examples/test_tacc_deps.sh
# or, to clone NCAR/hrldas into $WORK in the same pass (only if all probes pass):
bash /path/to/noahmp-skill-public/examples/test_tacc_deps.sh --clone
```

The script runs six probes (host, compilers, netCDF, Jasper, NCAR Fortran/C
tarball, summary) and exits non-zero if any fail. Its summary block prints the
recommended `./configure` choice and a ready-to-paste `user_build_options`
stanza with real ls6 paths.

With `--clone`, a seventh phase runs only if all probes passed: it does
`git clone --recurse-submodules https://github.com/NCAR/hrldas` into `$WORK`
(skipped if `$WORK/hrldas` already exists). If the user opts in here, they
can jump straight to Phase 4 below.

If anything fails:

| Symptom | Remediation |
|---------|-------------|
| `ifort not in PATH` | `module load intel` |
| `gfortran/gcc not in PATH` | `module load gcc` |
| `no netcdf.inc under /opt/apps` | `module load netcdf` |
| `libjasper missing` | `module load jasper` (only required if building `create_forcing.exe`) |
| TEST_4 link failed | Compiler ABI mismatch — `module purge` and reload `intel` + `netcdf` from a clean state |
| Download failed | The user is probably on a compute node. Move to a login node. |

Re-run the script after each remediation until it exits 0.

**STOP — ask user:** "Did the script exit 0 and print a recommended
`./configure` option? Paste the summary block — I'll keep it for Phase 4."

Capture from the script output:

- The recommended `./configure` choice (should be **3 — ifort serial** on ls6).
- The `NETCDFMOD` / `NETCDFLIB` / `LIBJASPER` / `INCJASPER` stanza.

---

## Phase 2 — Clone the source

Skip this phase if the user already ran `test_tacc_deps.sh --clone` in
Phase 1; otherwise clone into `$WORK`, not `$HOME`.

```bash
cd "$WORK"
git clone --recurse-submodules https://github.com/NCAR/hrldas
cd hrldas
ls noahmp/src | head                              # expect ~136 *.F90 files including NoahmpMainMod.F90
```

If the user forgot `--recurse-submodules` (the empty `noahmp/` symptom from
`reference/getting-started.md`):

```bash
git submodule update --init --recursive
```

**STOP — ask user:** "Is `noahmp/src/NoahmpMainMod.F90` present? If yes,
we're ready to configure. If no, run the submodule update above."

---

## Phase 3 — Stage the build options

Two layers, in this order:

1. Run `./configure` first (Phase 4) — it writes a `user_build_options` file
   from a template.
2. Then merge in the ls6-specific stanza from Phase 1.

For reference, the canonical ls6 build options from the source transcript
(KW-PHS-Note0 cell 36) live at:

> https://github.com/ktwu01/Ori_RPM/blob/main/hrldas_phs/hrldas/user_build_options_TACC

Treat this as a known-working **reference**, not a drop-in replacement —
library versions on ls6 may have moved since it was captured. The dep-test
script's summary takes precedence for `NETCDFMOD/LIB` and `LIBJASPER/INCJASPER`
because it reads the current filesystem.

**STOP — ask user:** "Want to fetch the reference file for side-by-side
diff with what `./configure` will write? (Optional — most users just paste
the script summary.)"

---

## Phase 4 — Configure

```bash
cd "$WORK/hrldas/hrldas"
./configure
```

The interactive prompt looks like (from KW-PHS-Note0 cell 14):

```
Please select from following supported architectures:

   1. Linux PGI compiler serial
   2. Linux PGI compiler MPI
   3. Linux ifort compiler serial      ← ls6: pick this
   4. Linux ifort compiler MPI
   5. Linux gfortran compiler serial
   6. Linux ifort compiler MPI for compy
   0. exit only

Enter selection [1-5] :
```

On ls6, options 1–2 are unusable (`pgfortran` is absent — confirmed by the
dep test). Option 3 (ifort serial) matches what the Phase 1 script
recommended and what the upstream TACC `user_build_options_TACC` file targets.

**STOP — ask user:** "I'm about to send `3` to `./configure`. Confirm?"

After it returns, edit `user_build_options` and replace the four library
lines with the stanza from Phase 1:

```makefile
NETCDFMOD   = -I/opt/apps/intel19/netcdf/4.6.2/x86_64/include
NETCDFLIB   = -L/opt/apps/intel19/netcdf/4.6.2/x86_64/lib -lnetcdff -lnetcdf
LIBJASPER   = -L<from script>/lib -ljasper
INCJASPER   = -I<from script>/include
```

If the user plans to debug a build problem rather than run for real, add
ifort debug flags (`-O0 -g -check all -traceback -fpe0`) to `F90FLAGS` — see
`getting-started.md` Step 5. Strip them again before production.

**STOP — ask user:** "`user_build_options` now points at the ls6 netCDF
and Jasper paths from the dep test. Ready to build?"

---

## Phase 5 — Build

```bash
make clean
make >& compile.log
```

Watch for the exit:

```bash
echo "make exit: $?"                                       # expect 0
grep -in -E 'error|cannot|undefined reference' compile.log | head -20
ls -la run/hrldas.exe                                      # the artifact
```

Expected build time on an ls6 login node: 1–3 minutes. If it's much slower,
the user may have wandered onto a contended login node — let them retry on
another login (login1/login2).

If `make` exit ≠ 0:

| Pattern in `compile.log` | Likely cause | Fix |
|--------------------------|--------------|-----|
| `cannot find -lnetcdff` | netCDF Fortran binding path wrong in `user_build_options` | Re-paste the Phase 1 stanza |
| `Symbol not found: __netcdf_MOD_*` | netCDF built with a different compiler than ifort | The "broken" entries in the script's netCDF probe — switch to the `intel19/netcdf` build |
| `catastrophic error: Too many errors, exiting` | Same as above (gcc-built netCDF + ifort source) | Same fix |
| `cannot find -ljasper` | Jasper module not loaded | `module load jasper`, regrab `LIBJASPER` from re-running the dep test |
| Build silently completes but `hrldas.exe` missing | First error in submodule build was suppressed | `make clean && make >& compile.log`, search log for the first `Error` |

Re-run from `make clean` after each fix — partial-rebuilds with stale `.mod`
files lie to you.

**STOP — ask user:** "Does `ls run/hrldas.exe` show the executable? Size
should be ~20–80 MB depending on debug flags."

---

## Phase 6 — Handoff

You're done with setup. From here:

- **Smoke test the executable** (Step 7 of `getting-started.md`): `cd run &&
  ./hrldas.exe` should at least print a banner; it will error on missing
  forcing unless `INDIR`/`OUTDIR` are set, which is the next document's
  job.
- **One site, one year:** `reference/running-single-point.md`.
- **A real domain (e.g. Texas at 12.5 km):** `reference/running-2d-domain.md`,
  then `reference/designing-a-run.md` for the planning checklist, then
  `examples/PLAN_Texas_12p5km_NLDAS2_TACC.md` for a worked example on this
  exact cluster.
- **Before any run that's not a quick `./hrldas.exe` print-banner check:**
  drop to a compute node. `idev -p development -t 02:00:00` is the
  interactive option; sbatch templates are documented in the TACC user
  guide. Login nodes are CPU-throttled and your real run will be slow and
  visible to TACC admins.

**STOP — ask user:** "Where do you want to go next: smoke test the
executable, single-point run, or jump to the Texas 2D plan?"
