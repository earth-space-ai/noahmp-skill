# Contributing to Noah-MP via Pull Request

Noah-MP is a community model. New physics, bug fixes, and documentation
improvements all flow through GitHub pull requests reviewed by the Noah-MP
Code Review Committee. This guide walks through the standard contribution
flow.

Tutorial source (borrowed and learned from Cenlin He's Noah-MP tutorial):
https://github.com/NCAR/hrldas/blob/master/tutorial/Note4_Code_Development_GitHub_Pull_Request.ipynb
GitHub guide:
https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request

---

## The two-repo gotcha

Because `noahmp` is a submodule of `hrldas`, virtually every meaningful
contribution touches **both** repos:

- The new physics / fix / output → `NCAR/noahmp`
- The HRLDAS coupling layer (IO transfer, namelist, table read, restart) →
  `NCAR/hrldas`

That means you fork **both** repos, commit to **both** repos, and submit
**two PRs**. Get this wrong and one of your PRs has a dangling submodule
reference.

---

## Step 1: Fork both repos

On the GitHub web UI:
1. Visit https://github.com/NCAR/noahmp → click **Fork**.
2. Visit https://github.com/NCAR/hrldas → click **Fork**.

Both forks land under your account, e.g. `<you>/noahmp` and `<you>/hrldas`.

**Before you start coding:** sync your fork with the official repo so you are
not branching off stale code. Click the "Sync fork" button on each fork's
GitHub page until it says "Up to date with NCAR:master" and "NCAR:develop".

---

## Step 2: Add your fork as a second remote

After cloning the official repo with submodules:

```bash
git clone --recurse-submodules https://github.com/NCAR/hrldas
cd hrldas
git remote
# → origin            (this is NCAR)
```

Add your fork as an alias (`<alias>` is whatever short name you like):

```bash
git remote add <alias> https://github.com/<you>/hrldas/
git remote
# → origin
# → <alias>
```

Repeat for the noahmp submodule:

```bash
cd noahmp
git remote add <alias> https://github.com/<you>/noahmp/
git remote
```

---

## Step 3: Switch to the `develop` branch

All new contributions branch off `develop`, never `master`.

```bash
cd ~/path/to/hrldas
git fetch <alias>
git checkout develop

cd noahmp
git fetch <alias>
git checkout develop
```

This is where you make and commit your changes.

---

## Step 4: Make changes and commit (atomic, granular)

Follow the project rule: one logical change per commit. The custom-output
example (`BTRANXY`) is six file edits across two repos, but conceptually one
change, commit it as one commit per repo, not six.

In the **noahmp** submodule directory:

```bash
git status         # see modified files
git add drivers    # add specific paths, never `git add -A` blindly
git status         # confirm staging
git commit -m "create extra BTRANXY output variable"
# → [develop 5f53ef5] create extra BTRANXY output variable
#   4 files changed, 5 insertions(+)
```

In the **hrldas** repo:

```bash
git status hrldas
git add hrldas/IO_code/module_NoahMP_hrldas_driver.F
git commit -m "create extra BTRANXY output variable"
# → [develop 305c74e] create extra BTRANXY output variable
#   1 file changed, 1 insertion(+)
```

---

## Step 5: Push, submodule first, driver second

**Critical order:** push the submodule (`noahmp`) to your fork **before**
pushing the driver (`hrldas`). The driver records the submodule's commit
SHA. If you push the driver first, your `hrldas` PR will reference a
submodule commit that does not yet exist on your noahmp fork, anyone
cloning your branch will get a "fatal: reference is not a tree" error.

```bash
cd noahmp
git push <alias> develop
# → enter GitHub username + personal access token

cd ..
git push <alias> develop
```

---

## Step 6: Open the pull requests

On the GitHub web UI for **each** fork:

1. Visit your fork (`https://github.com/<you>/noahmp`).
2. GitHub will detect your recent push and offer "Compare & pull request" , 
   click it.
3. Set base: `NCAR:develop`, compare: `<you>:develop`.
4. Title: short, action-verb (e.g., "Add BTRANXY output variable").
5. Description: what changed, why, what testing was done. Reference any
   companion PR ("requires NCAR/noahmp#NNN", "companion to NCAR/hrldas#MMM").
6. Request **Cenlin He (cenlinhe)** as the reviewer (or whomever the current
   committee pages directs to).
7. Repeat for the hrldas fork.

The bottom of each PR page shows the diff between `NCAR:develop` and
`<you>:develop`, verify only your intended changes appear.

---

## Step 7: Iterate during review

The Noah-MP Code Review Committee will:

- Inspect physics correctness
- Test compilation and basic regression
- Comment on style / structure
- Request changes if needed

Push additional commits to your `develop` branch in the same direction (push
submodule first again on each iteration), they automatically attach to the
open PR.

When approved, a committee member merges into `NCAR:develop`. During the
annual release cycle, `develop` merges into `master` for the official
version release.

---

## Common contribution pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| `fatal: reference is not a tree` on PR | Pushed driver before submodule | Push submodule first |
| PR diff includes unrelated whitespace changes | Editor reformatted other files | `git checkout -- <unrelated_file>` to discard unwanted changes before committing |
| Reviewer asks why your `noahmp/` SHA jumped | You committed a submodule update without pushing the new submodule commits | Push submodule first |
| GitHub asks for password and rejects | GitHub deprecated password auth | Generate a personal access token (PAT) and use it as the password |
| "Branches have diverged" after fork-sync | Worked on stale `develop` | Rebase: `git fetch origin; git rebase origin/develop` (or open a fresh branch) |
| Submodule pointer stuck | After pulling driver, submodule HEAD detaches | `cd noahmp && git checkout develop && git pull <alias> develop` |

---

## License + contributor expectations

Noah-MP is governed by the NCAR/noahmp license:
https://github.com/NCAR/noahmp/blob/develop/LICENSE.txt

The Code Review Committee expects:

- New physics options come with a peer-reviewed reference.
- Bug fixes come with a regression test or before/after comparison.
- New parameters added to `NoahmpTable.TBL` are documented in the table
  comments and in the namelist README.
- New physics is **off by default** (gated by a new namelist option),
  preserving bit-identical reproduction of prior behavior.

---

## Where to next

- The end-to-end custom-output example used here: `custom-output.md`
- Diagnose build / runtime / output problems: `debugging.md`
