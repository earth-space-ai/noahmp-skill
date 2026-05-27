#!/usr/bin/env bash
# check_run_outputs.sh — post-run verification for a Noah-MP / HRLDAS simulation.
#
# Runs after hrldas.exe finishes (single-point OR 2D). Probes the "did the
# model actually do something sensible?" failure modes that are silent if
# you only check the exit code: zero-byte LDASOUT files, start-date /
# forcing mismatch, missing executable permissions on the next run, custom
# output variable not actually exported, etc.
#
# Designed for the AI-native pathway: the agent calls this script over the
# same SSH session it used to run the model, parses [PASS]/[WARN]/[FAIL]
# lines, and surfaces failures to the user before continuing.
#
# Usage
#   bash check_run_outputs.sh <RUN_DIR> [--forcing-dir DIR] [--var NAME]
#
#   <RUN_DIR>          directory containing namelist.hrldas and *.LDASOUT_DOMAIN1
#   --forcing-dir DIR  forcing directory to cross-check against namelist
#                      (default: read INDIR from namelist.hrldas)
#   --var NAME         additionally verify that LDASOUT contains NAME
#                      (use after Note3-style custom-output edits)
#
# Exit 0 iff all checks pass. WARN does not fail; FAIL does.
#
# This is the post-run companion to examples/test_tacc_deps.sh (pre-run
# build deps). The two together cover the lifecycle gates: "can I build?"
# and "did the run produce believable output?".

set -u

RUN_DIR=""
FORCING_DIR=""
CUSTOM_VAR=""

while (( $# > 0 )); do
  case "$1" in
    --forcing-dir) FORCING_DIR="$2"; shift 2 ;;
    --var)         CUSTOM_VAR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "unknown option: $1" >&2; exit 2 ;;
    *)
      RUN_DIR="$1"; shift ;;
  esac
done

if [[ -z "$RUN_DIR" ]]; then
  echo "usage: bash check_run_outputs.sh <RUN_DIR> [--forcing-dir DIR] [--var NAME]" >&2
  exit 2
fi

if [[ ! -d "$RUN_DIR" ]]; then
  echo "error: $RUN_DIR is not a directory" >&2
  exit 2
fi

# ---- output helpers ---------------------------------------------------------
RED=$'\033[0;31m'; YEL=$'\033[0;33m'; GRN=$'\033[0;32m'; BLD=$'\033[1m'; OFF=$'\033[0m'
pass() { printf "  ${GRN}[PASS]${OFF} %s\n" "$*"; }
warn() { printf "  ${YEL}[WARN]${OFF} %s\n" "$*"; }
fail() { printf "  ${RED}[FAIL]${OFF} %s\n" "$*"; FAILED=1; }
note() { printf "         %s\n" "$*"; }
hdr()  { printf "\n${BLD}== %s ==${OFF}\n" "$*"; }

FAILED=0
NAMELIST="$RUN_DIR/namelist.hrldas"

# ---- 1. Namelist present ----------------------------------------------------
hdr "1. Namelist sanity"
if [[ -f "$NAMELIST" ]]; then
  pass "namelist.hrldas found in $RUN_DIR"
else
  fail "no namelist.hrldas in $RUN_DIR"
  note "remediate: copy from hrldas/run/namelist.hrldas.template or examples/single_point/"
  exit 1
fi

# Extract a few values for downstream checks. Strip quotes, whitespace,
# inline comments.
nl_get() {
  grep -i "^[[:space:]]*$1[[:space:]]*=" "$NAMELIST" 2>/dev/null \
    | head -1 \
    | sed -E "s/^[^=]*=[[:space:]]*//;s/[[:space:]]*!.*$//;s/^[\"']//;s/[\"'][[:space:]]*$//;s/[[:space:]]*$//"
}

NL_INDIR="$(nl_get INDIR)"
NL_OUTDIR="$(nl_get OUTDIR)"
NL_START_YEAR="$(nl_get START_YEAR)"
NL_START_MONTH="$(nl_get START_MONTH)"
NL_START_DAY="$(nl_get START_DAY)"
NL_DYNVEG="$(nl_get DYNAMIC_VEG_OPTION)"
NL_SPINUP="$(nl_get SPINUP_LOOPS)"

# ---- 2. INDIR / OUTDIR resolve ---------------------------------------------
hdr "2. Namelist paths resolve"
# Paths in HRLDAS namelists are typically relative to the run directory.
resolve_dir() {
  local d="$1"
  [[ -z "$d" ]] && return 1
  if [[ "$d" = /* ]]; then echo "$d"; else echo "$RUN_DIR/$d"; fi
}

INDIR_ABS="$(resolve_dir "$NL_INDIR")" || true
OUTDIR_ABS="$(resolve_dir "$NL_OUTDIR")" || true

if [[ -n "$INDIR_ABS" && -d "$INDIR_ABS" ]]; then
  pass "INDIR resolves: $INDIR_ABS"
else
  fail "INDIR missing or not a directory: ${INDIR_ABS:-<unset>}"
  note "remediate: edit INDIR in $NAMELIST to point at your LDASIN forcing dir"
fi

if [[ -n "$OUTDIR_ABS" && -d "$OUTDIR_ABS" ]]; then
  pass "OUTDIR resolves: $OUTDIR_ABS"
else
  warn "OUTDIR missing: ${OUTDIR_ABS:-<unset>}"
  note "remediate: mkdir -p \"$OUTDIR_ABS\"  (HRLDAS will not create it)"
fi

# ---- 3. START_DATE vs first forcing file ------------------------------------
hdr "3. START_DATE matches first forcing file"
if [[ -n "$INDIR_ABS" && -d "$INDIR_ABS" ]]; then
  # Look for either *.LDASIN_DOMAIN1 (preferred) or YYYYMMDDHHMM.txt
  first_forcing="$(ls "$INDIR_ABS"/*.LDASIN_DOMAIN1 2>/dev/null | head -1)"
  if [[ -z "$first_forcing" ]]; then
    first_forcing="$(ls "$INDIR_ABS"/[0-9]*[0-9].txt 2>/dev/null | head -1)"
  fi
  if [[ -n "$first_forcing" ]]; then
    stamp="$(basename "$first_forcing" | grep -oE '^[0-9]{8,12}')"
    if [[ -n "$stamp" ]]; then
      fyy="${stamp:0:4}"; fmm="${stamp:4:2}"; fdd="${stamp:6:2}"
      nyy="$(printf '%04d' "${NL_START_YEAR:-0}" 2>/dev/null || echo 0000)"
      nmm="$(printf '%02d' "${NL_START_MONTH:-0}" 2>/dev/null || echo 00)"
      ndd="$(printf '%02d' "${NL_START_DAY:-0}" 2>/dev/null || echo 00)"
      if [[ "$fyy$fmm$fdd" == "$nyy$nmm$ndd" ]]; then
        pass "namelist START=$nyy-$nmm-$ndd matches first forcing $fyy-$fmm-$fdd"
      else
        fail "START mismatch: namelist=$nyy-$nmm-$ndd, first forcing=$fyy-$fmm-$fdd"
        note "remediate: align START_YEAR/MONTH/DAY in $NAMELIST with the forcing range"
      fi
    else
      warn "could not parse date from $first_forcing"
    fi
  else
    warn "no LDASIN_DOMAIN1 or YYYYMMDD*.txt files in $INDIR_ABS"
  fi
fi

# ---- 4. Output files exist and are non-empty -------------------------------
hdr "4. Output files (LDASOUT_DOMAIN1)"
search_dir="${OUTDIR_ABS:-$RUN_DIR}"
# Portable file list (bash 3.x has no mapfile)
out_files=()
while IFS= read -r line; do
  out_files+=("$line")
done < <(find "$search_dir" -maxdepth 2 -name '*.LDASOUT_DOMAIN1' 2>/dev/null)
n_out="${#out_files[@]}"
if (( n_out == 0 )); then
  fail "no *.LDASOUT_DOMAIN1 files under $search_dir"
  note "remediate: model did not write output. Check hrldas.exe stdout/stderr."
else
  pass "$n_out LDASOUT files found"
  # Check the largest one for non-trivial size (>10 KB → real data, not header-only)
  biggest="$(ls -S "${out_files[@]}" 2>/dev/null | head -1)"
  biggest_size=$(stat -c '%s' "$biggest" 2>/dev/null || stat -f '%z' "$biggest" 2>/dev/null)
  if [[ -n "$biggest_size" && "$biggest_size" -gt 10240 ]]; then
    pass "largest output $biggest is $biggest_size bytes (>10 KB)"
  else
    fail "largest output $biggest is only ${biggest_size:-?} bytes — likely a header-only file"
    note "remediate: model crashed early. Check the runtime log and the namelist physics options."
  fi
fi

# ---- 5. LH variable not silently zero --------------------------------------
hdr "5. LH variable sanity"
if (( n_out > 0 )) && command -v ncdump >/dev/null 2>&1; then
  sample="${out_files[0]}"
  if ncdump -v LH "$sample" 2>/dev/null | grep -q 'LH ='; then
    # Pull the LH values; flag if every printed value is "0," or "_," (fill)
    lh_lines="$(ncdump -v LH "$sample" 2>/dev/null | sed -n '/LH =/,/;/p' | tr -d ' \n' )"
    if [[ -n "$lh_lines" ]] && grep -qE '[1-9]' <<<"$lh_lines"; then
      pass "LH in $sample has non-zero values"
    else
      fail "LH in $sample is all zeros/fill — DYNAMIC_VEG_OPTION mismatch?"
      note "remediate: see reference/running-single-point.md 'Common single-point pitfalls'."
      note "current DYNAMIC_VEG_OPTION in namelist: ${NL_DYNVEG:-<unset>}"
    fi
  else
    warn "LH variable not present in $sample (acceptable for some custom builds)"
  fi
else
  note "skipping (ncdump not available or no output files)"
fi

# ---- 6. Custom output variable present (only with --var) -------------------
if [[ -n "$CUSTOM_VAR" ]]; then
  hdr "6. Custom output variable: $CUSTOM_VAR"
  if (( n_out > 0 )) && command -v ncdump >/dev/null 2>&1; then
    if ncdump -h "${out_files[0]}" 2>/dev/null | grep -qE "(float|double)[[:space:]]+$CUSTOM_VAR\\b"; then
      pass "$CUSTOM_VAR is in the LDASOUT variable list"
    else
      fail "$CUSTOM_VAR not found in LDASOUT — compile-time edit did not propagate to output"
      note "remediate: see reference/custom-output.md. Likely missing add_to_output call."
    fi
  fi
fi

# ---- 7. SPINUP_LOOPS sanity -------------------------------------------------
hdr "7. SPINUP_LOOPS sanity"
if [[ -n "$NL_SPINUP" ]]; then
  if [[ "$NL_SPINUP" =~ ^[0-9]+$ ]] && (( NL_SPINUP <= 20 )); then
    pass "SPINUP_LOOPS=$NL_SPINUP (reasonable)"
  elif [[ "$NL_SPINUP" =~ ^[0-9]+$ ]]; then
    warn "SPINUP_LOOPS=$NL_SPINUP is unusually high — runtime will be ~${NL_SPINUP}x the base period"
    note "if intentional (long spin-up for arid soils), ignore. Otherwise reduce."
  else
    warn "SPINUP_LOOPS=$NL_SPINUP is non-numeric"
  fi
else
  note "SPINUP_LOOPS not set in namelist (treated as 0)"
fi

# ---- 8. Executable still present and runnable for next run -----------------
hdr "8. hrldas.exe ready for re-run"
if [[ -x "$RUN_DIR/hrldas.exe" ]]; then
  pass "$RUN_DIR/hrldas.exe is executable"
elif [[ -f "$RUN_DIR/hrldas.exe" ]]; then
  fail "$RUN_DIR/hrldas.exe exists but is not executable"
  note "remediate: chmod +x \"$RUN_DIR/hrldas.exe\""
else
  warn "no hrldas.exe in $RUN_DIR (may live elsewhere if you separate src/run dirs)"
fi

# ---- Summary ----------------------------------------------------------------
hdr "Summary"
if (( FAILED == 0 )); then
  echo "  ${GRN}All checks passed.${OFF}"
  if [[ -n "$CUSTOM_VAR" ]]; then
    echo "  Custom variable $CUSTOM_VAR is present in LDASOUT — proceed to validation."
  fi
  exit 0
else
  echo "  ${RED}${BLD}One or more checks failed.${OFF} Fix the items marked [FAIL] before treating this run as valid."
  exit 1
fi
