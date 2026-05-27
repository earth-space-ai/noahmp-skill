# Reference outputs

Known-good model outputs from non-AI tutorial runs, kept here so an
AI-native run can be diffed against them.

| File | What it is | Source |
|------|-----------|--------|
| `bondville_LH_ncview.png` | `ncview` LH (latent heat, W/m²) timeseries for one day at the Bondville site, single-point run, 48 × 30-min timesteps. Shows the canonical diurnal shape: ~0 W/m² overnight, ramp at sunrise, ~420 W/m² peak in mid-afternoon UTC, taper to evening. | Captured by running the NCAR/hrldas tutorial (https://github.com/NCAR/hrldas/blob/master/tutorial/Note1_Single_Point.ipynb) through to its `ncview 199806200030.LDASOUT_DOMAIN1` step on the LH variable. |

## How AI-native runs are compared to these

After a Bondville run completes via the AI-native playbook (the Step 6
block in `reference/running-single-point.md`), the agent calls
`examples/plot_ldasout_lh.py` to produce a headless matplotlib version of
the same plot from the run's LDASOUT files, then surfaces both side-by-side
to the user. The visual match doesn't have to be pixel-perfect — what
matters is the diurnal shape: timing of the morning ramp, height of the
afternoon peak, magnitude of overnight values. A flat-line LH plot is the
"`DYNAMIC_VEG_OPTION` mismatch" bug captured in the single-point pitfalls
table.
