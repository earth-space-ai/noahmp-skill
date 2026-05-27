# AI-native setup on TACC Lonestar6

Claude takes a user from a fresh ls6 login to a working `hrldas.exe`.
**Claude does the work**: opens an SSH session to ls6, runs each phase via
`Bash`, parses output, decides the next step, and only asks the user at
irreversible decision points (credentials, allocation, configure choice,
final ship). End state is a built executable; running the model is covered
by `running-single-point.md` and `running-2d-domain.md`.

Source: distilled from KW-Mod-Tutorials `KW-PHS-Note0_Download_Compile.ipynb`
(ls6 terminal transcripts). Stampede3 / Frontera variants are out of scope.

---

## How Claude executes this

This is not a checklist for the human to read. It is a script for Claude
to run. Concretely:

1. **Open one persistent SSH session.** Use `Bash` with `run_in_background:
   true` for `ssh -o ControlMaster=auto -o ControlPath=~/.ssh/cm-%r@%h:%p
   -o ControlPersist=10m <user>@ls6.tacc.utexas.edu`. All subsequent phase
   commands reuse the multiplex socket — same shell environment carries
   over, so `module load` in Phase 1 stays loaded in Phase 5.
2. **Run each phase's `command_block` end-to-end** via that SSH session.
   Capture stdout+stderr.
3. **Apply the phase's `success_check`** to the captured output. On
   success, advance silently. On failure, run the matching remediation
   from `failure_modes`, then re-run the phase. Cap remediations at 3
   attempts before surfacing to the user.
4. **Ask the user only at points marked `USER GATE`**. Those are the
   irreversible or judgment calls: SSH credentials, allocation/budget
   confirmation, the `./configure` keystroke, and the final "build looks
   right?" sign-off.
5. **`module load` is Claude's job here**, not the user's. The Bash
   environment is Claude's SSH session, not the user's shell — loading a
   module only affects this session and persists until the ControlPersist
   timeout. This is the inversion from the human-driven version: the
   reason the old guide said "don't auto-load" was to protect the user's
   shell, which Claude isn't touching.
6. **Trust the dep-test script.** Don't re-derive what its PASS/FAIL
   verdicts already encode.

---

## Phase 0 — Pre-flight (USER GATE)

**Inputs Claude needs from the user before opening the session:**

- ls6 username (or confirmation that `~/.ssh/config` has an `ls6` Host entry)
- Project allocation Claude should bill against (or confirmation that the
  default in `~/.tacc_profile` is correct)

Ask both in one `AskUserQuestion` round, then proceed.

**Commands Claude runs after the gate:**

```bash
hostname -f
echo "WORK=$WORK"     && ls "$WORK"     2>/dev/null | head
echo "SCRATCH=$SCRATCH" && ls "$SCRATCH" 2>/dev/null | head
test -f /usr/local/etc/taccinfo && cat /usr/local/etc/taccinfo
```

**`success_check`:**
- `hostname -f` matches `*.ls6.tacc.utexas.edu`
- `$WORK` is non-empty and the directory exists
- `taccinfo` shows non-zero balance on at least one project

**`failure_modes`:**

| Symptom | Claude does |
|---------|-------------|
| `hostname` doesn't match ls6 | Surface to user: wrong host, confirm SSH target |
| Compute node (`c???-???`) | `exit` the SSH session; reconnect — the rest of the playbook needs outbound network |
| `$WORK` unset | `source /etc/profile && source ~/.bashrc`; if still unset, surface to user (broken account) |
| Zero allocation | Surface to user: cannot proceed without an allocation |

---

## Phase 1 — Dependency test

**Pre-step:** Claude uploads `examples/test_tacc_deps.sh` to `~/test_tacc_deps.sh`
on ls6 (`scp` over the same multiplex socket, or `cat | ssh ... 'cat >
~/test_tacc_deps.sh'`).

**Command Claude runs:**

```bash
chmod +x ~/test_tacc_deps.sh

# Build-chain only:
bash ~/test_tacc_deps.sh --clone
echo "__EXIT__=$?"

# OR, when the user's request involves NLDAS-2 / 2D-domain forcing
# (e.g. examples/PLAN_Texas_12p5km_NLDAS2_TACC.md), also probe the forcing
# toolchain in the same pass:
bash ~/test_tacc_deps.sh --clone --forcing
echo "__EXIT__=$?"
```

**Claude picks the flag set from the user's stated goal in Phase 0:**

| User goal | Flags Claude uses |
|-----------|-------------------|
| "Just build hrldas.exe", "single-point Bondville run" | `--clone` |
| Anything mentioning NLDAS-2, 2D domain, CONUS, a state-scale region | `--clone --forcing` |
| Unclear | Ask the user once at the Phase 0 gate. Default to `--clone --forcing` if they handwave — the extra probes are cheap and don't write anything. |

**`success_check`:**
- `__EXIT__=0`
- Output contains `Recommended ./configure choice on ls6: 3`
- Output contains a `NETCDFMOD = -I...` line
- Output contains either `clone complete; noahmp submodule populated` or
  `$WORK/hrldas already exists`

**Claude captures, in variables for later phases:**
- `RECOMMENDED_CONFIGURE_OPT` — the integer after "Recommended ./configure choice on ls6:"
- `USER_BUILD_OPTIONS_STANZA` — the four lines (NETCDFMOD, NETCDFLIB, LIBJASPER, INCJASPER) from the summary block
- `HRLDAS_DIR` — `$WORK/hrldas` (from the clone confirmation)

**`failure_modes`** (Claude applies the first match, then re-runs Phase 1):

| `[FAIL]` line | Claude runs |
|---------------|-------------|
| `ifort not in PATH` | `module load intel` |
| `gfortran not in PATH` or `gcc not in PATH` | `module load gcc` |
| `no netcdf.inc under /opt/apps` | `module load netcdf` |
| `no libjasper` (and the build will need create_forcing.exe) | `module load jasper` |
| `TEST_4: link failed (Fortran↔C ABI mismatch)` | `module purge && module load intel netcdf` |
| `download failed` | `module load wget` if missing, else surface (likely compute-node misroute) |
| `$WORK is unset` in Phase 7 of the script | Already handled in Phase 0; should not reach here |
| **Forcing-block (only when `--forcing` was set):** | |
| `wgrib not in PATH` | `module load wgrib` (or `module load grads` on some ls6 versions which bundles it) |
| `~/.netrc not found` or `no urs.earthdata.nasa.gov machine entry` | **USER GATE** — Claude cannot fabricate credentials. Ask the user to register at `https://urs.earthdata.nasa.gov` and create the `.netrc` entry, then proceed |
| `NLDAS_ELEVATION.grb.gz present but not uncompressed` | `gzip -d $WORK/hrldas/HRLDAS_forcing/run/examples/NLDAS/NLDAS_ELEVATION.grb.gz` (idempotent, safe to auto-run) |
| `perl modules missing: …` | Try the system perl first by re-running; on ls6 the listed modules are always available. If still failing, `cpanm <module>` per the hint. |

If three remediation cycles do not yield exit 0, **surface to user** with
the full script output and ask whether to continue manually.

---

## Phase 2 — Verify clone (no USER GATE)

The `--clone` in Phase 1 already cloned the repo. Claude verifies:

```bash
ls "$HRLDAS_DIR/noahmp/src/NoahmpMainMod.F90"
ls "$HRLDAS_DIR/hrldas" | head
```

**`success_check`:** `NoahmpMainMod.F90` exists; `hrldas/` subdir contains `configure`.

**`failure_modes`:** if the .F90 is missing, run
`cd "$HRLDAS_DIR" && git submodule update --init --recursive`, then re-check.

---

## Phase 3 — Stage build options (no USER GATE)

Claude fetches the canonical reference once for diffing:

```bash
curl -sLo /tmp/user_build_options_TACC.ref \
  https://raw.githubusercontent.com/ktwu01/Ori_RPM/main/hrldas_phs/hrldas/user_build_options_TACC
head -40 /tmp/user_build_options_TACC.ref
```

The reference is for sanity-checking only — the Phase 1 stanza takes
precedence because it reflects the current `/opt/apps` state.

If `curl` fails (network blocked from this node, repo moved), Claude
proceeds without the reference and notes it in the final summary.

---

## Phase 4 — Configure (USER GATE on keystroke)

`./configure` is interactive. Claude drives it but pauses for one final
confirmation before sending the digit.

```bash
cd "$HRLDAS_DIR/hrldas"
./configure <<EOF_INPUT
__USER_CONFIRMED_OPT__
EOF_INPUT
```

**USER GATE:** Before submitting, Claude asks:

> "Phase 1 recommended `./configure` option **3** (Linux ifort compiler
> serial) based on the ls6 dep test. The other options on this host are
> either unavailable (PGI) or unusual for this workflow. Confirm 3, or
> override?"

Then substitutes the confirmed integer for `__USER_CONFIRMED_OPT__`.

After `./configure` returns, Claude patches `user_build_options` with
`USER_BUILD_OPTIONS_STANZA` from Phase 1:

```bash
cd "$HRLDAS_DIR/hrldas"
# Claude generates this sed/awk block from USER_BUILD_OPTIONS_STANZA,
# replacing each of NETCDFMOD / NETCDFLIB / LIBJASPER / INCJASPER in place.
python3 - <<'PY'
import re, os, pathlib
p = pathlib.Path("user_build_options")
text = p.read_text()
for line in os.environ["USER_BUILD_OPTIONS_STANZA"].splitlines():
    if "=" not in line: continue
    key = line.split("=", 1)[0].strip()
    text = re.sub(rf"(?m)^{re.escape(key)}\s*=.*$", line.strip(), text)
p.write_text(text)
PY
grep -E '^(NETCDFMOD|NETCDFLIB|LIBJASPER|INCJASPER)' user_build_options
```

**`success_check`:** all four lines `grep`'d back match the Phase 1 stanza.

**`failure_modes`:** if any line is missing from `user_build_options` (the
configure template structure changed), Claude appends the stanza at the
end of the file with a header comment.

---

## Phase 5 — Build (no USER GATE)

```bash
cd "$HRLDAS_DIR/hrldas"
make clean
make >& compile.log
echo "__MAKE_EXIT__=$?"
ls -la run/hrldas.exe 2>/dev/null
grep -in -E 'error|cannot|undefined reference' compile.log | head -20
```

**`success_check`:** `__MAKE_EXIT__=0` and `run/hrldas.exe` exists with
nonzero size.

**`failure_modes`:**

| `grep` pattern from `compile.log` | Claude runs |
|-----------------------------------|-------------|
| `cannot find -lnetcdff` | Re-extract netCDF stanza from Phase 1, re-patch `user_build_options`, `make clean && make >& compile.log` |
| `Symbol not found: __netcdf_MOD_*` or `catastrophic error: Too many errors` | The loaded netCDF was compiled with a different toolchain. `module purge && module load intel netcdf`, re-run Phase 1 to refresh `NETCDF_GOOD`, then Phase 5 |
| `cannot find -ljasper` | `module load jasper`, re-run Phase 1, re-patch, rebuild |
| Exit 0 but `hrldas.exe` missing | An earlier silent failure in a sub-make. Surface to user with the first non-warning line of `compile.log` |

Three failed attempts → surface with full `compile.log` (or a `tail -100`).

---

## Phase 6 — Final sign-off (USER GATE)

Claude prints:

- `ls -la "$HRLDAS_DIR/hrldas/run/hrldas.exe"` (size, mtime)
- Loaded modules (`module list`)
- Path to `user_build_options` and a diff against the canonical reference
- Where outputs will land (`$SCRATCH` reminder)

Then asks:

> "Build complete. Next step: smoke test the executable, set up a single-point
> run, or jump to the Texas 12.5 km plan?"

The next-step options route to:
- **Single-point (Bondville-style):** `reference/running-single-point.md`.
  Forcing here is `bondville.dat` + `create_point_data.exe`; no NLDAS-2 or
  Earthdata involved. If the user picked this branch but Phase 1 ran with
  `--forcing`, the NLDAS-2 probes were wasted but harmless.
- **2D / NLDAS-2:** `reference/designing-a-run.md` → `reference/running-2d-domain.md`
  → `examples/PLAN_Texas_12p5km_NLDAS2_TACC.md`. Confirm the `--forcing`
  probes all passed (especially `~/.netrc` + `wgrib`) before the user
  starts the GES DISC download — a 3-day window is ~30 MB but a multi-year
  run is hundreds of GB.
- **Just-confirm-it-builds:** `reference/getting-started.md` Step 7 for the
  bare banner check.

Remind once: any non-trivial run requires `idev -p development -t 02:00:00`
or sbatch — not the login node Claude is on.

---

## What's NOT Claude's job

- **Editing the user's `~/.bashrc`.** Modules loaded in Claude's SSH session
  evaporate when the ControlPersist expires. That is correct — the user's
  shell stays clean.
- **Picking the allocation.** Phase 0 asks; Claude doesn't infer.
- **Submitting sbatch jobs.** Out of scope here; lives in
  `running-2d-domain.md`.
- **Long-running builds in the background.** A 1–3 minute `make` is
  foreground. If the SSH session drops mid-build, Phase 5 re-runs from
  `make clean` cleanly.
