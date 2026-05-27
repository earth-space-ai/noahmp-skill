#!/usr/bin/env bash
# test_tacc_deps.sh — verify Noah-MP / HRLDAS build dependencies on TACC Lonestar6.
#
# What it does
#   Six probes, each prints [PASS] / [WARN] / [FAIL] with a one-line hint.
#     1. Host check          — confirm ls6.tacc.utexas.edu
#     2. Compiler probe      — locate ifort, gfortran, gcc, cpp (pgfortran is unavailable on ls6)
#     3. netCDF probe        — find netcdf.inc; flag known-good vs broken builds under /opt/apps
#     4. Jasper probe        — find libjasper (needed by create_forcing.exe)
#     5. Fortran/C dep tests — download the NCAR WRF tarball; build and run TEST_1..4 + csh/perl/sh
#     6. Summary             — print recommended ./configure option and a ready-to-paste
#                              user_build_options stanza
#
# Exit 0 only if all six probes pass. The script does not run `module load`;
# it reports what is missing and lets the user load modules themselves.
#
# Side effects: creates ~/test_noahmp_deps/ and downloads ~150 KB into it.
#
# Source: distilled from KW-PHS-Note0_Download_Compile.ipynb (cells 14, 16, 36, 51, 55).
# Companion playbook: reference/setup-tacc.md

set -u

WORKDIR="${HOME}/test_noahmp_deps"
FORTRAN_C_URL="https://www2.mmm.ucar.edu/wrf/OnLineTutorial/compile_tutorial/tar_files/Fortran_C_tests.tar"

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
  echo "  Next: open reference/setup-tacc.md and continue from Phase 2 (clone the repo)."
  exit 0
else
  echo
  echo "  ${RED}${BLD}One or more checks failed.${OFF} Fix the items marked [FAIL] above before continuing."
  echo "  Common first move on ls6: ${BLD}module load intel netcdf${OFF} (and ${BLD}module load jasper${OFF} if building create_forcing.exe), then re-run."
  exit 1
fi
