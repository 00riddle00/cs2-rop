<!-- vim: set ft=markdown tw=88 nu ai et ts=2 sw=2: -->
<!-- markdownlint-disable-file MD041 -->

**Course:** Data Mining (5 ECTS), VU GMC and VU MIF, Autumn 2026

**Study programs:** MSc Bioinformatics, MSc Data Science

**Project:** Counter-Strike 2 demo parsing and analysis

**_cs2-rop_** is a university Data Mining project exploring data extracted from
**Counter-Strike 2 (CS2) match demos**. This repository brings together a Go-based
snapshot exporter, Python analysis using [Awpy](https://github.com/pnxenopoulos/awpy),
and a Jupyter notebook for examining parser output.

**Current status:** The repository provides a working parsing and inspection workflow
for two MOUZ vs. Spirit matches (Dust2 and Mirage). It is a starting point for the
team's data-mining work, not yet a finished analysis or predictive model.

**Parameters and description:**

- Timeframe: 01.08.2026 - 11.10.2026
- Teams: TOP 10 Between each other [HLTV]
- Games: LAN
- Maps: Dust2, Mirage
- Snapshots: Every 5 seconds, (320 ticks)
- Variables:
- [In-Game] Side, Coordinates, Health, Round time, Win condition, Economy, Weapons, Utilities, Alive/Dead, X vs. X, C4 Position
- [Meta] Teams, Players, Player ranking, Team ranking, History
- Goal: Round outcome prediction based on position & other variables
- H0: Round outcomes are random and independent on position & other in-game variables
- H1: Round outcomes are predictable and dependent on position & other in-game variables

Check for more detail in PAR_DESC.txt.

## Table of contents

<!--toc:start-->
- [Table of contents](#table-of-contents)
- [Overview](#overview)
- [Quick start](#quick-start)
- [Repository layout](#repository-layout)
- [Parse demos with Go](#parse-demos-with-go)
- [Explore the data in Jupyter](#explore-the-data-in-jupyter)
- [Data organization and CSV columns](#data-organization-and-csv-columns)
- [Development commands](#development-commands)
  - [Environment and parser verification](#environment-and-parser-verification)
- [Troubleshooting](#troubleshooting)
<!--toc:end-->

## Overview

The project currently consists of:

- [`go-parser/`](./go-parser/) (Go, using
  [demoinfocs-golang](https://github.com/markus-wa/demoinfocs-golang)): exports player
  snapshots from `.dem` files to CSV.
- [Awpy](https://github.com/pnxenopoulos/awpy) (Python): parses demos for exploration
  and analysis.
- [`parser_check.ipynb`](./notebooks/parser_check.ipynb) (Jupyter): inspects Awpy data
  and the Go-exported CSVs.

The Go exporter provides compact positional snapshots, while Awpy offers detailed event
data such as kills, damage, and grenades. Their outputs have different schemas.

## Quick start

You need Git, [uv](https://docs.astral.sh/uv/getting-started/installation/), and
[Go](https://go.dev/doc/install) (Go 1.27.2+). uv manages Python:
[`.python-version`](./.python-version) pins **3.13.16**, so you do not need to install
Python manually.

The commands below work on Linux, macOS, and native Windows PowerShell;
[WSL](https://learn.microsoft.com/en-us/windows/wsl/install) is not required.
Windows users can obtain Git from [Git for Windows](https://git-scm.com/downloads/win).

1. **Clone the repository.** On its GitHub page, select **Code**, copy the HTTPS or SSH
   clone URL, and run:

   ```bash
   git clone <repository-url>
   cd cs2-rop
   ```

   Run all subsequent commands from the repository root.

2. **Install dependencies:**

   ```bash
   uv sync
   go -C go-parser mod download
   ```

   uv creates a local `.venv/` and downloads the pinned Python version if necessary. You
   can use `uv run ...` without activating the environment.

3. **Download demos** from the shared
   [Drive](https://drive.google.com/drive/folders/1UgOOA8CaxJsiOhflHg3al98Yb-lQi989).

   Place these files in [`data/raw/`](./data/raw/):

   ```text
   data/raw/mouz-vs-spirit-m1-dust2.dem
   data/raw/mouz-vs-spirit-m2-mirage.dem
   ```

   Do not commit `.dem` files: they may exceed GitHub's 100 MiB file limit.
   [`.gitignore`](./.gitignore) excludes them, and
   [`data/raw/.gitkeep`](./data/raw/.gitkeep) preserves the directory in Git.

4. **Generate or refresh the CSVs:**

   ```bash
   go -C go-parser run . --input ../data/raw/mouz-vs-spirit-m1-dust2.dem
   go -C go-parser run . --input ../data/raw/mouz-vs-spirit-m2-mirage.dem
   ```

   The results are written to [`data/processed/`](./data/processed/). If you have GNU
   Make, `make setup` and `make parse` are shortcuts for steps 2 and 4.

5. **Explore the results** in
   [`notebooks/parser_check.ipynb`](./notebooks/parser_check.ipynb); see [Explore the
   data in Jupyter](#explore-the-data-in-jupyter).

The small CSVs in [`data/processed/`](./data/processed/) and
[`data/samples/`](./data/samples/) are committed to Git and can be inspected without raw
demos. Parsing with Go or Awpy requires the corresponding `.dem` files.

## Repository layout

```text
cs2-rop/
├── data/                        # Datasets (see below)
├── go-parser/                   # Go module and parser (main.go)
├── notebooks/                   # Jupyter notebooks
├── src/cs2_rop/                 # Python package
├── Makefile                     # Setup and development commands
├── .gitignore                   # Git ignore rules
├── cspell.json                  # Spell-checker configuration
├── pyproject.toml               # Python dependencies and configuration
├── uv.lock                      # Locked Python dependencies
└── .python-version              # Pinned Python interpreter
```

The Go parser is a separate module under [`go-parser/`](./go-parser/), with its own
[`go.mod`](./go-parser/go.mod) and [`go.sum`](./go-parser/go.sum). No repository-level
`go.work` file is needed.

## Parse demos with Go

The Go parser requires `--input` and accepts an optional `--output`. By default, it
writes `data/processed/<demo-name>_snapshots.csv`. An existing CSV with the same name is
**overwritten**.

The `go -C go-parser` command changes the working directory to `go-parser/`, so paths
passed to the parser are relative to that directory (hence `../data/raw/` above).

To choose an output file, append `--output ../data/processed/dust2_custom.csv` to a
parsing command. With Make, you can run `make parse-dust2` or `make parse-mirage`
individually; `make all` performs setup and parses both demos.

## Explore the data in Jupyter

Open the [parser inspection notebook](./notebooks/parser_check.ipynb) in a
Jupyter-capable editor, such as VS Code with its Python and
[Jupyter](https://code.visualstudio.com/docs/datascience/jupyter-notebooks) extensions.
The project's `ipykernel` dependency is installed by `uv sync`. Select the `.venv`
Python environment as the kernel, then run cells in order.

In the notebook's configuration cell, select the full match identifier:

```python
match_name = "mouz-vs-spirit-m1-dust2"
# match_name = "mouz-vs-spirit-m2-mirage"
```

Dust2 is match **1** (`m1`); Mirage is match **2** (`m2`). You can start the notebook
from either the repository root or `notebooks/`. The Awpy section needs the
corresponding `.dem` file; the CSV inspection section works with committed data.

Notebook execution may save large outputs, execution counts, or local paths. Review `git
diff` before committing notebook changes.

## Data organization and CSV columns

| Directory                              | Contents                   | Tracked by Git?       |
| -------------------------------------- | -------------------------- | --------------------- |
| [`data/raw/`](./data/raw/)             | Original `.dem` recordings | No, except `.gitkeep` |
| [`data/processed/`](./data/processed/) | Snapshot CSVs              | Yes, while small      |
| [`data/samples/`](./data/samples/)     | Example CSVs               | Yes                   |

**Sampling:** During active rounds, the Go exporter records player states every **320
demo ticks** (approximately **5 seconds** at 64 ticks per second). Each snapshot has one
row per player, including dead players. For a normal 5v5 match, this typically means ten
rows per sampled tick. These are not full per-tick trajectories or event logs; account
for the sampling interval when computing time-dependent features.

The current Go snapshot CSVs contain:

| Column        | Meaning                                                           |
| ------------- | ----------------------------------------------------------------- |
| `tick`        | Demo tick associated with the snapshot.                           |
| `round_num`   | Round number.                                                     |
| `steamid`     | Steam identifier (not a numeric measurement).                     |
| `name`        | Player name.                                                      |
| `team`        | Numeric side/team value, not a permanent organization identifier. |
| `alive`       | Whether the player is alive.                                      |
| `health`      | Player health.                                                    |
| `x`, `y`, `z` | Position in CS2 game-world coordinates.                           |

Row order is not a reliable key for comparing data: use match, round, tick, and player
identifiers.

## Development commands

The [`Makefile`](./Makefile) lists its targets with `make help`. Useful shortcuts:

- `make pylint`: Ruff and Black for Python.
- `make golint`: `go fmt` and `go vet` for Go.
- `make shlint`: [ShellCheck](https://github.com/koalaman/shellcheck) and
  [shfmt](https://github.com/mvdan/sh) for shell scripts (install separately).
- `make lint`: Run all three lint/format targets.
- `make check-env`: Verify the Python environment, dependencies, Go compilation, and
  required datasets.
- `make smoke-test`: Run environment checks, verify both raw demo checksums, parse both
  demos, and compare every output row against the tracked references.
- `make clean`: Remove disposable caches, preserving environments and datasets.

To lint and format without Make (including in native Windows PowerShell), run from the
repository root:

```bash
go -C go-parser fmt ./...
go -C go-parser vet ./...
uv run ruff check . --fix
uv run black .
```

**Linting targets also modify files** through automatic fixes and formatting. Inspect
`git diff` afterwards.

### Environment and parser verification

After `uv sync` and downloading both demos, run from the repository root:

```text
make check-env
make smoke-test
```

Without GNU Make, use these equivalent commands in native Windows PowerShell, Linux, or
macOS:

```text
uv run --no-sync python -B scripts/verify.py check-env
uv run --no-sync python -B scripts/verify.py smoke-test
```

Verification requires uv, Go 1.27.2+ (as specified by `go-parser/go.mod`), and the
project `.venv` using the exact interpreter pinned in `.python-version`. It checks
dependency compatibility with `uv pip check`, imports runtime packages, exercises
dataframe conversion, and compiles Go with `-mod=readonly`. It does not check exact
dependency versions against the lockfile or install or synchronize Python dependencies;
run `uv sync` to synchronize the environment. Go may populate its normal
dependency/build caches or download a required toolchain.

Both raw demos and both `data/processed/` reference CSVs are required. `check-env`
checks demo headers and validates CSV schemas, field types, and unique player keys.
`smoke-test` also requires Git on `PATH` and rejects staged or unstaged changes to
either reference CSV relative to `HEAD`. Review and commit intentional reference updates
before testing against the new baseline; unrelated file changes are allowed. This checks
regression against the current commit, not the baseline's scientific validity.
`smoke-test` additionally checks both raw SHA-256 values before parsing either demo. The
expected values in [`data/raw_checksums.json`](./data/raw_checksums.json) identify the
project's local baseline demos; they were not independently verified against the shared
download source.

The compiled binary and generated CSVs use a temporary directory that is removed on
completion or failure. Tracked datasets are never overwritten. CSV comparisons ignore
row order and line endings but require exact field values, including the parser's
three-decimal coordinates. Failures print diagnostics and return a nonzero exit code.
The notebook is neither executed nor modified by these commands.

These two Makefile targets require no Bash or Unix utilities and can run with a native
Windows GNU Make installation. Existing lint and cleanup targets still require the Unix
utilities described below.

When changing dependencies, commit [`uv.lock`](./uv.lock) alongside
[`pyproject.toml`](./pyproject.toml), or [`go.sum`](./go-parser/go.sum) alongside
[`go.mod`](./go-parser/go.mod), as applicable.

GNU Make is optional: all essential setup and parsing commands appear in Quick start.
For the existing lint and cleanup targets on Windows, run Make in an environment such as
[MSYS2](https://www.msys2.org/) or WSL, with [GNU
Make](https://www.gnu.org/software/make/) and Unix utilities installed. Git Bash alone
may not include Make.

## Troubleshooting

- **`uv` or `go` is not recognized:** Check `uv --version` or `go version`, and ensure
  the tool is installed and on `PATH`.
- **The notebook cannot import a package:** Confirm `uv sync` completed, check the
  selected Python interpreter, and restart the kernel. The interpreter is usually
  `.venv/Scripts/python.exe` on Windows or `.venv/bin/python` on Linux/macOS.
