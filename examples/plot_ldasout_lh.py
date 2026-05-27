#!/usr/bin/env python3
"""Plot LH (latent heat, W/m^2) from a single day of LDASOUT files.

Designed for the AI-native Bondville single-point verification step
(reference/running-single-point.md Step 6). Produces a headless PNG that
roughly matches the ncview reference at
examples/reference_outputs/bondville_LH_ncview.png — same axes, same shape
expectations, no GUI dependency. The agent runs this after hrldas.exe
finishes and surfaces the output PNG alongside the reference.

Usage
-----
  python3 examples/plot_ldasout_lh.py <OUTDIR> [--date YYYYMMDD] [-o PNG]

  <OUTDIR>        directory containing *.LDASOUT_DOMAIN1 files
  --date          which 24h block to plot (default: first day found)
  -o, --output    output PNG path (default: ./bondville_LH.png)

The script discovers timestep files by filename pattern
YYYYMMDDHHMM.LDASOUT_DOMAIN1, reads the LH variable from each, and plots
the timeseries. For single-point runs every file has shape (1, 1); the
scalar is what gets plotted.

Why the script (and not ncview):
  - SSH sessions to TACC typically have no X-forwarding; ncview opens an
    X window and that window is what was captured in the tutorial PNG.
  - matplotlib renders headlessly with the 'Agg' backend, writes a PNG
    the agent can attach to the conversation, and is deterministic enough
    to compare across runs.

Dependencies: numpy, netCDF4 (or xarray), matplotlib. All available in
the TACC python3 module or any conda env.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys
from pathlib import Path


def _load_lh(path: str) -> float:
    """Return the scalar LH value (W/m^2) from one LDASOUT file."""
    try:
        from netCDF4 import Dataset  # type: ignore
    except ImportError:
        # Fallback to xarray if netCDF4 is not directly importable
        import xarray as xr  # type: ignore
        with xr.open_dataset(path) as ds:
            return float(ds["LH"].values.flatten()[0])
    with Dataset(path) as ds:
        return float(ds.variables["LH"][:].flatten()[0])


def _parse_stamp(filename: str) -> tuple[str, str] | None:
    """Extract (YYYYMMDD, HHMM) from a LDASOUT filename, or None."""
    m = re.match(r"(\d{8})(\d{4})\.LDASOUT_DOMAIN1$", os.path.basename(filename))
    if not m:
        return None
    return m.group(1), m.group(2)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("outdir", help="directory containing *.LDASOUT_DOMAIN1 files")
    p.add_argument("--date", help="YYYYMMDD to plot (default: first day found)")
    p.add_argument(
        "-o",
        "--output",
        default="bondville_LH.png",
        help="output PNG path (default: ./bondville_LH.png)",
    )
    args = p.parse_args(argv)

    files = sorted(glob.glob(os.path.join(args.outdir, "*.LDASOUT_DOMAIN1")))
    if not files:
        print(f"error: no *.LDASOUT_DOMAIN1 files under {args.outdir}", file=sys.stderr)
        return 1

    # Group by date
    by_date: dict[str, list[tuple[str, str]]] = {}
    for f in files:
        parsed = _parse_stamp(f)
        if not parsed:
            continue
        date, hhmm = parsed
        by_date.setdefault(date, []).append((hhmm, f))

    if not by_date:
        print(f"error: no files matched YYYYMMDDHHMM.LDASOUT_DOMAIN1 in {args.outdir}", file=sys.stderr)
        return 1

    target_date = args.date or sorted(by_date.keys())[0]
    if target_date not in by_date:
        print(
            f"error: --date={target_date} not found. Available: {sorted(by_date)}",
            file=sys.stderr,
        )
        return 1

    day_files = sorted(by_date[target_date])
    lh_values = [_load_lh(f) for _, f in day_files]
    timesteps = list(range(len(lh_values)))

    print(f"plotting {len(lh_values)} timesteps from {target_date}")
    print(f"  LH range: {min(lh_values):.1f} to {max(lh_values):.1f} W/m^2")

    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(timesteps, lh_values, "o-", color="red", markersize=3, linewidth=1)
    ax.set_xlabel("Time (timestep index)")
    ax.set_ylabel("LH (W/m^2)")
    ax.set_title(f"LH at Bondville, {target_date}")
    ax.set_ylim(-100, 500)  # match ncview reference y-range
    ax.grid(True, alpha=0.4, linestyle=":")
    ax.text(
        0.02,
        0.95,
        "LH",
        transform=ax.transAxes,
        fontsize=16,
        fontweight="bold",
        verticalalignment="top",
    )
    fig.tight_layout()
    out_path = Path(args.output).resolve()
    fig.savefig(out_path, dpi=120)
    print(f"wrote {out_path}")

    # Quick sanity assertion: flat-line LH is a sign of the DYNAMIC_VEG_OPTION
    # bug from the single-point pitfalls table. Surface it loudly.
    if max(lh_values) - min(lh_values) < 5.0:
        print(
            "WARNING: LH is essentially flat across the day. This is the "
            "DYNAMIC_VEG_OPTION mismatch bug — see "
            "reference/running-single-point.md 'Common single-point pitfalls'.",
            file=sys.stderr,
        )
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
