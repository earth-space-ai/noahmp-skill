#!/usr/bin/env bash
# test_tacc_deps.sh — verify Noah-MP / HRLDAS build (and optional forcing)
# dependencies on TACC Lonestar6.
#
# Usage
#   bash test_tacc_deps.sh                     # build-chain probes only
#   bash test_tacc_deps.sh --clone             # also clone hrldas into $WORK if all probes PASS
#   bash test_tacc_deps.sh --forcing           # also probe NLDAS-2 forcing toolchain
#   bash test_tacc_deps.sh --clone --forcing   # everything (recommended for 2D-domain workflows)
#
# What it does
#   Build-chain probes (always run; PASS/[WARN]/[FAIL]):
#     1. Host check          — confirm ls6.tacc.utexas.edu
#     2. Compiler probe      — locate ifort, gfortran, gcc, cpp (pgfortran is unavailable on ls6)
#     3. netCDF probe        — find netcdf.inc; flag known-good vs broken builds under /opt/apps
#     4. Jasper probe        — find libjasper (needed by create_forcing.exe)
#     5. Fortran/C dep tests — download the NCAR WRF tarball; build and run TEST_1..4 + csh/perl/sh
#     6. Summary             — print recommended ./configure option and a ready-to-paste
#                              user_build_options stanza
#
#   With --forcing (additional probes; only relevant for 2D / NLDAS-2 workflows):
#     F1. wgrib              — required by create_forcing.exe to read NLDAS GRIB
#     F2. perl + modules     — extract_nldas.perl needs perl plus a few standard modules
#     F3. .netrc Earthdata   — NASA GES DISC won't serve NLDAS-2 without urs.earthdata.nasa.gov auth
#     F4. NLDAS_ELEVATION    — sanity-check for the bundled elevation grid under $WORK/hrldas
#                              (only if --clone has run or $WORK/hrldas already exists)
#
#   With --clone (only if all probes PASS):
#     7. Clone source        — git clone --recurse-submodules https://github.com/NCAR/hrldas
#                              into $WORK (skipped if $WORK/hrldas already exists)
#
# Exit 0 only if all probes pass (build-chain plus any opt-in groups requested),
# and the clone, if requested, succeeded. The script does not run `module load`;
# it reports what is missing and lets the user (or driving agent) load modules
# themselves.
#
# Side effects: creates ~/test_noahmp_deps/ and downloads ~150 KB into it.
# With --clone: also creates $WORK/hrldas (~250 MB after submodule init).
# Never writes to ~/.netrc, ~/.bashrc, or any module state.
#
# Source: captured while following the NCAR/hrldas tutorial on Lonestar6
# (https://github.com/NCAR/hrldas/blob/master/tutorial/Note0_Download_Compile.ipynb)
# and reference/running-2d-domain.md.
# Companion playbook: reference/setup-tacc.md

set -u

DO_CLONE=0
DO_FORCING=0
for arg in "$@"; do
  case "$arg" in
    --clone)   DO_CLONE=1 ;;
    --forcing) DO_FORCING=1 ;;
    -h|--help)
      sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

WORKDIR="${HOME}/test_noahmp_deps"
FORTRAN_C_URL="https://www2.mmm.ucar.edu/wrf/OnLineTutorial/compile_tutorial/tar_files/Fortran_C_tests.tar"
HRLDAS_URL="https://github.com/NCAR/hrldas"

# ---- output helpers ---------------------------------------------------------
RED=$'\033[0;31m'; YEL=$'\033[0;33m'; GRN=$'\033[0;32m'; BLD=$'\033[1m'; OFF=$'\033[0m'
pass() { printf "  ${GRN}[PASS]${OFF} %s\n" "$*"; }
warn() { printf "  ${YEL}[WARN]${OFF} %s\n" "$*"; WARNED=1; }
fail() { printf "  ${RED}[FAIL]${OFF} %s\n" "$*"; FAILED=1; }
note() { printf "         %s\n" "$*"; }
hdr()  { printf "\n${BLD}== %s ==${OFF}\n" "$*"; }

FAILED=0
WARNED=0

# Recorded values for the summary
IFORT_PATH=""
GFORTRAN_PATH=""
GCC_PATH=""
NETCDF_GOOD=""        # directory of the recommended netCDF build (parent of include/)
JASPER_DIR=""

# ---- 1. Host check ----------------------------------------------------------
hdr "1. Host check"
HOST="$(hostname -f 2>/dev/null || hostname)"
case "$HOST" in
  *.ls6.tacc.utexas.edu|ls6.tacc.utexas.edu|login*.ls6*)
    pass "running on ls6 ($HOST)"
    ;;
  *.tacc.utexas.edu|*frontera*|*stampede*)
    warn "TACC system detected but not ls6 ($HOST). This script is tuned for ls6; results may still be useful."
    ;;
  *)
    warn "not a TACC ls6 login node ($HOST). Continuing anyway — useful for a dry run from a laptop."
    ;;
esac

# ---- 2. Compiler probe ------------------------------------------------------
hdr "2. Compiler probe"
for c in ifort gfortran gcc cpp; do
  if path="$(command -v "$c" 2>/dev/null)"; then
    pass "$c → $path"
    case "$c" in
      ifort)    IFORT_PATH="$path" ;;
      gfortran) GFORTRAN_PATH="$path" ;;
      gcc)      GCC_PATH="$path" ;;
    esac
  else
    fail "$c not in PATH"
    case "$c" in
      ifort)    note "remediate: module load intel" ;;
      gfortran|gcc|cpp) note "remediate: module load gcc" ;;
    esac
  fi
done
# pgfortran is *expected* to be absent on ls6 — record but do not fail.
if command -v pgfortran >/dev/null 2>&1; then
  note "pgfortran present (unusual on ls6): $(command -v pgfortran)"
else
  note "pgfortran absent (expected on ls6 — do not pick configure options 1 or 2)"
fi

# ---- 3. netCDF probe --------------------------------------------------------
hdr "3. netCDF probe (find /opt/apps -name netcdf.inc)"
# Verdicts captured in the source transcript (cell 55). Portable (no
# associative arrays — those need bash ≥ 4 which ls6 has, but the script
# should still dry-run on a Mac with bash 3.2).
nc_verdict() {
  case "$1" in
    /opt/apps/intel19/netcdf/4.6.2/x86_64/include/netcdf.inc)                 echo good ;;
    /opt/apps/intel19/impi19_0/parallel-netcdf/4.6.2/x86_64/include/netcdf.inc) echo broken ;;
    /opt/apps/gcc9_4/netcdf/4.6.2/x86_64/include/netcdf.inc)                   echo broken ;;
    /opt/apps/gcc11_2/impi19_0/amber/20.0/include/netcdf.inc)                  echo broken ;;
    /opt/apps/gcc11_2/netcdf/4.7.4/x86_64/include/netcdf.inc)                  echo broken ;;
    *)                                                                         echo unknown ;;
  esac
}

# Honour an already-loaded netCDF module if present.
if [[ -n "${TACC_NETCDF_DIR:-}" && -f "$TACC_NETCDF_DIR/include/netcdf.inc" ]]; then
  pass "module-loaded netCDF: \$TACC_NETCDF_DIR=$TACC_NETCDF_DIR"
  NETCDF_GOOD="$TACC_NETCDF_DIR"
elif [[ -d /opt/apps ]]; then
  mapfile -t NC_INCS < <(find /opt/apps -name netcdf.inc 2>/dev/null)
  if (( ${#NC_INCS[@]} == 0 )); then
    fail "no netcdf.inc under /opt/apps"
    note "remediate: module load netcdf  (then re-run this script)"
  else
    for inc in "${NC_INCS[@]}"; do
      case "$(nc_verdict "$inc")" in
        good)
          pass "$inc  (known-good with ifort serial)"
          [[ -z "$NETCDF_GOOD" ]] && NETCDF_GOOD="${inc%/include/netcdf.inc}"
          ;;
        broken)
          warn "$inc  (known to break Noah-MP build — do not use)"
          ;;
        *)
          note "$inc  (unclassified — try if no known-good option loads cleanly)"
          ;;
      esac
    done
    if [[ -z "$NETCDF_GOOD" ]]; then
      fail "no known-good netCDF build found"
      note "remediate: module load netcdf  (TACC default ifort19 build)"
    fi
  fi
else
  warn "/opt/apps not present — not on TACC; skipping netCDF discovery"
fi

# ---- 4. Jasper probe --------------------------------------------------------
hdr "4. Jasper probe"
if [[ -n "${TACC_JASPER_DIR:-}" && -f "$TACC_JASPER_DIR/include/jasper/jasper.h" ]]; then
  pass "module-loaded Jasper: \$TACC_JASPER_DIR=$TACC_JASPER_DIR"
  JASPER_DIR="$TACC_JASPER_DIR"
elif [[ -d /opt/apps ]]; then
  mapfile -t JAS_LIBS < <(find /opt/apps -name 'libjasper.*' 2>/dev/null | head -5)
  if (( ${#JAS_LIBS[@]} > 0 )); then
    for lib in "${JAS_LIBS[@]}"; do
      pass "libjasper → $lib"
    done
    JASPER_DIR="$(dirname "$(dirname "${JAS_LIBS[0]}")")"
  else
    warn "no libjasper under /opt/apps"
    note "remediate: module load jasper   (only required if you build create_forcing.exe)"
  fi
else
  warn "/opt/apps not present — skipping Jasper discovery"
fi

# ---- 5. NCAR Fortran/C dependency tests -------------------------------------
hdr "5. NCAR Fortran/C dependency tests"
if [[ -z "$GFORTRAN_PATH" || -z "$GCC_PATH" ]]; then
  fail "skipping — gfortran and gcc are both required for this test"
else
  mkdir -p "$WORKDIR"
  cd "$WORKDIR" || { fail "cannot cd to $WORKDIR"; exit 1; }

  if [[ ! -f Fortran_C_tests.tar ]]; then
    note "downloading $FORTRAN_C_URL → $WORKDIR"
    if command -v wget >/dev/null 2>&1; then
      wget -q "$FORTRAN_C_URL" || true
    elif command -v curl >/dev/null 2>&1; then
      curl -sLO "$FORTRAN_C_URL" || true
    else
      fail "neither wget nor curl is available"
    fi
    if [[ ! -f Fortran_C_tests.tar ]]; then
      fail "download failed (network/proxy issue, or this is a compute node with no outbound network)"
      note "remediate: run from a login node, or fetch the tarball manually and place it in $WORKDIR"
    fi
  else
    note "Fortran_C_tests.tar already present"
  fi

  if [[ -f Fortran_C_tests.tar ]]; then
    tar -xf Fortran_C_tests.tar
    run_test() {
      local name="$1"; shift
      local expected="$1"; shift
      rm -f a.out
      if ! "$@" >/dev/null 2>&1; then
        fail "$name: compile failed"
        return
      fi
      out="$(./a.out 2>&1 || true)"
      if grep -q "$expected" <<<"$out"; then
        pass "$name"
      else
        fail "$name: did not see expected '$expected' in output"
        note "got: $(head -1 <<<"$out")"
      fi
    }

    run_test "TEST_1 fortran fixed format"  "SUCCESS test 1" \
      gfortran TEST_1_fortran_only_fixed.f
    run_test "TEST_2 fortran free format"   "SUCCESS test 2" \
      gfortran TEST_2_fortran_only_free.f90
    run_test "TEST_3 C only"                "SUCCESS test 3" \
      gcc TEST_3_c_only.c

    # TEST_4 is multi-step; run inline so we can fail at the right stage.
    rm -f a.out
    if   ! gcc      -c -m64 TEST_4_fortran+c_c.c          >/dev/null 2>&1; then fail "TEST_4: gcc -c failed"
    elif ! gfortran -c -m64 TEST_4_fortran+c_f.f90        >/dev/null 2>&1; then fail "TEST_4: gfortran -c failed"
    elif ! gfortran   -m64 TEST_4_fortran+c_f.o TEST_4_fortran+c_c.o >/dev/null 2>&1; then
      fail "TEST_4: link failed (Fortran↔C ABI mismatch)"
    else
      out="$(./a.out 2>&1 || true)"
      if grep -q "SUCCESS test 4" <<<"$out"; then
        pass "TEST_4 fortran calling C"
      else
        fail "TEST_4: ran but did not print SUCCESS"
      fi
    fi

    for s in TEST_csh.csh TEST_perl.pl TEST_sh.sh; do
      label="${s#TEST_}"; label="${label%.*} script"
      if [[ ! -x "$s" ]]; then
        fail "$s: missing or not executable"
      elif "./$s" 2>&1 | grep -q "SUCCESS"; then
        pass "$label"
      else
        fail "$label: no SUCCESS in output"
      fi
    done
  fi
fi

# ---- F. Forcing toolchain (opt-in via --forcing) ----------------------------
# Only relevant for 2D/NLDAS-2 workflows (reference/running-2d-domain.md).
# Single-point users (running-single-point.md) can skip this entirely — they
# use bondville.dat + create_point_data.exe, neither of which needs wgrib,
# extract_nldas.perl, or NASA Earthdata.
if (( DO_FORCING == 1 )); then
  hdr "F. NLDAS-2 forcing toolchain"

  # F1. wgrib — required by extract_nldas.perl and create_forcing.exe
  if path="$(command -v wgrib 2>/dev/null)"; then
    pass "wgrib → $path"
  elif path="$(command -v wgrib2 2>/dev/null)"; then
    warn "wgrib not found, but wgrib2 is available at $path"
    note "extract_nldas.perl uses classic 'wgrib' syntax; wgrib2 is not a drop-in."
    note "remediate: module load wgrib  (or build wgrib from source)"
  else
    fail "wgrib not in PATH"
    note "remediate: module load wgrib  (NLDAS-2 GRIB cannot be read without it)"
  fi

  # F2. perl + the few modules extract_nldas.perl pulls in
  if path="$(command -v perl 2>/dev/null)"; then
    pass "perl → $path ($(perl -e 'print $^V' 2>/dev/null))"
    missing_mods=""
    for m in strict warnings File::Path File::Copy; do
      perl -M"$m" -e1 >/dev/null 2>&1 || missing_mods="$missing_mods $m"
    done
    if [[ -n "$missing_mods" ]]; then
      warn "perl modules missing:$missing_mods"
      note "remediate: cpanm$missing_mods  (or rely on the system perl, usually fine on ls6)"
    else
      note "core perl modules (strict, warnings, File::Path, File::Copy) all importable"
    fi
  else
    fail "perl not in PATH (extract_nldas.perl cannot run)"
  fi

  # F3. NASA Earthdata .netrc — required to download NLDAS-2 from GES DISC.
  # We only check presence + the urs.earthdata.nasa.gov line; we never read
  # or print credentials.
  if [[ ! -f "$HOME/.netrc" ]]; then
    warn "~/.netrc not found"
    note "remediate: register at https://urs.earthdata.nasa.gov, then add to ~/.netrc:"
    note "  machine urs.earthdata.nasa.gov login YOUR_USERNAME password YOUR_PASSWORD"
    note "  chmod 600 ~/.netrc"
  else
    perms="$(stat -c '%a' "$HOME/.netrc" 2>/dev/null || stat -f '%Lp' "$HOME/.netrc" 2>/dev/null)"
    if [[ "$perms" != "600" && "$perms" != "400" ]]; then
      warn "~/.netrc exists but permissions are $perms (must be 600 or wget/curl will refuse to use it)"
      note "remediate: chmod 600 ~/.netrc"
    fi
    if grep -q "urs.earthdata.nasa.gov" "$HOME/.netrc"; then
      pass "~/.netrc has urs.earthdata.nasa.gov entry (perms=$perms)"
    else
      warn "~/.netrc exists but no urs.earthdata.nasa.gov machine entry"
      note "remediate: add 'machine urs.earthdata.nasa.gov login USER password PASS' (chmod 600)"
    fi
  fi

  # F4. NLDAS_ELEVATION grid — bundled with hrldas. Only check if the source
  # tree is present (either via --clone earlier, or pre-existing).
  if [[ -n "${WORK:-}" && -d "${WORK}/hrldas" ]]; then
    elev_dir="${WORK}/hrldas/HRLDAS_forcing/run/examples/NLDAS"
    if [[ -f "$elev_dir/NLDAS_ELEVATION.grb" ]]; then
      pass "NLDAS_ELEVATION.grb already uncompressed at $elev_dir"
    elif [[ -f "$elev_dir/NLDAS_ELEVATION.grb.gz" ]]; then
      warn "NLDAS_ELEVATION.grb.gz present but not uncompressed"
      note "remediate: gzip -d $elev_dir/NLDAS_ELEVATION.grb.gz"
    else
      warn "no NLDAS_ELEVATION.grb[.gz] under $elev_dir"
      note "hrldas tree may be on a different release that ships it elsewhere; verify manually"
    fi
  else
    note "skipping NLDAS_ELEVATION check — \$WORK/hrldas not present yet (run with --clone first)"
  fi

  # F5. Reminder about what the user still needs to provide (not auto-checkable).
  note ""
  note "Not auto-checked (out of scope for a deps probe):"
  note "  - geo_em.d01_*.nc for your domain (WPS output, or tutorial's geo_em.d01_NLDAS0125.nc)"
  note "  - raw NLDAS-2 GRIB files in NLDAS_forcing/raw/ (download with NASA Earthdata creds)"
  note "  - extract_nldas.perl edits: \$data_dir, \$results_dir, year/day range"
  note "  See reference/running-2d-domain.md for the full procedure."
fi

# ---- 6. Summary -------------------------------------------------------------
hdr "6. Summary and recommended user_build_options"
if (( FAILED == 0 )); then
  echo
  echo "  All required dependencies present."
  echo
  echo "  ${BLD}Recommended ./configure choice on ls6:${OFF} 3  (Linux ifort compiler serial)"
  echo "    Reasons: ifort is the optimized Intel compiler, pgfortran is unavailable,"
  echo "    and the NoahMP test suite is regularly exercised with Intel on TACC."
  echo
  if [[ -n "$NETCDF_GOOD" || -n "$JASPER_DIR" ]]; then
    echo "  ${BLD}Paste this into user_build_options after ./configure writes the file:${OFF}"
    echo
    [[ -n "$NETCDF_GOOD" ]] && {
      echo "    NETCDFMOD   = -I${NETCDF_GOOD}/include"
      echo "    NETCDFLIB   = -L${NETCDF_GOOD}/lib -lnetcdff -lnetcdf"
    }
    [[ -n "$JASPER_DIR" ]] && {
      echo "    LIBJASPER   = -L${JASPER_DIR}/lib -ljasper"
      echo "    INCJASPER   = -I${JASPER_DIR}/include"
    }
    echo
  fi
  echo "  Reference TACC build options (canonical, ifort serial):"
  echo "    https://github.com/ktwu01/Ori_RPM/blob/main/hrldas_phs/hrldas/user_build_options_TACC"
  echo

  # ---- 7. Optional clone (only with --clone) --------------------------------
  if (( DO_CLONE == 1 )); then
    hdr "7. Clone NCAR/hrldas into \$WORK"
    if [[ -z "${WORK:-}" ]]; then
      fail "\$WORK is unset — are you on a TACC node? Set \$WORK to where you want the source, then re-run with --clone."
      exit 1
    elif [[ ! -d "$WORK" ]]; then
      fail "\$WORK ($WORK) does not exist."
      exit 1
    elif [[ -d "$WORK/hrldas/.git" ]]; then
      pass "$WORK/hrldas already exists — skipping clone."
      note "to refresh submodules anyway: cd $WORK/hrldas && git submodule update --init --recursive"
    else
      note "running: git clone --recurse-submodules $HRLDAS_URL  (into $WORK)"
      if ! command -v git >/dev/null 2>&1; then
        fail "git not in PATH (try: module load git)"
        exit 1
      fi
      if ( cd "$WORK" && git clone --recurse-submodules "$HRLDAS_URL" ); then
        if [[ -f "$WORK/hrldas/noahmp/src/NoahmpMainMod.F90" ]]; then
          pass "clone complete; noahmp submodule populated"
        else
          warn "clone finished but noahmp/src/NoahmpMainMod.F90 missing — running submodule update"
          ( cd "$WORK/hrldas" && git submodule update --init --recursive )
        fi
      else
        fail "git clone failed (network on a compute node? check from a login node)"
        exit 1
      fi
    fi
    echo
    echo "  Next: cd \$WORK/hrldas/hrldas && ./configure  (open reference/setup-tacc.md at Phase 4)."
  else
    echo "  Next: open reference/setup-tacc.md and continue from Phase 2 (clone the repo),"
    echo "        or re-run this script with --clone to clone NCAR/hrldas into \$WORK now."
  fi
  if (( DO_FORCING == 1 )); then
    echo
    echo "  Forcing toolchain probed (--forcing). For the full NLDAS-2 pipeline"
    echo "  (download, extract_nldas.perl, create_forcing.exe, namelist patching)"
    echo "  see reference/running-2d-domain.md."
  fi
  exit 0
else
  echo
  echo "  ${RED}${BLD}One or more checks failed.${OFF} Fix the items marked [FAIL] above before continuing."
  echo "  Common first move on ls6: ${BLD}module load intel netcdf${OFF} (and ${BLD}module load jasper${OFF} if building create_forcing.exe), then re-run."
  exit 1
fi
