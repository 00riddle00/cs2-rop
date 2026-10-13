<!-- vim: set ft=markdown tw=88 nu ai et ts=2 sw=2: -->

**Course:** Data Mining (5 ECTS), VU GMC and VU MIF, Autumn 2026

**Study programs:** MSc Bioinformatics, MSc Data Science

**Project:** Counter-Strike 2 demo parsing and analysis

**_cs2-rop_** is a university Data Mining project exploring data extracted from
**Counter-Strike 2 (CS2) match demos**. This repository brings together a Go-based
snapshot exporter, Python analysis using [Awpy](https://github.com/pnxenopoulos/awpy),
and a Jupyter notebook for examining parser output.

**Current status:** The repository provides a working parsing and inspection workflow
for two MOUZ vs. Spirit matches (Dust2 and Mirage). It is a starting point for the
team's data-mining work, **not yet a finished analysis or predictive model**.

## Table of contents

<!--toc:start-->
- [Table of contents](#table-of-contents)
- [Overview](#overview)
- [Quick start](#quick-start)
- [Prerequisites](#prerequisites)
  - [Windows](#windows)
  - [Linux and macOS](#linux-and-macos)
- [Repository layout](#repository-layout)
- [Set up the project](#set-up-the-project)
  - [With Make](#with-make)
  - [Without Make](#without-make)
- [Parse demos with Go](#parse-demos-with-go)
  - [Using Make targets](#using-make-targets)
  - [Running Go directly](#running-go-directly)
- [Explore the data in Jupyter](#explore-the-data-in-jupyter)
- [Data organization and CSV columns](#data-organization-and-csv-columns)
- [Development commands](#development-commands)
- [Troubleshooting](#troubleshooting)
- [References](#references)
<!--toc:end-->

## Overview

The project currently uses two complementary parsers:

| Component                                                           | Language         | Purpose                                                           |
| ------------------------------------------------------------------- | ---------------- | ----------------------------------------------------------------- |
| [demoinfocs-golang](https://github.com/markus-wa/demoinfocs-golang) | Go               | Read CS2 `.dem` files and export compact player snapshots as CSV. |
| [Awpy](https://github.com/pnxenopoulos/awpy)                        | Python           | Parse demo files for exploration and analysis in Python.          |
| [`notebooks/parser_check.ipynb`](./notebooks/parser_check.ipynb)    | Python / Jupyter | Inspect the Awpy result and the Go-exported snapshots.            |

The Go CSVs are *snapshots*: they contain selected player state at sampled moments,
not every possible event or statistic in a match. The Python and Go outputs serve
different purposes and should not be assumed to have identical schemas.

## Quick start

1. Clone the repository:

   ```bash
   git clone REPOSITORY_URL
   cd cs2-rop
   ```

2. Install [uv](https://docs.astral.sh/uv/getting-started/installation/) and
   [Go](https://go.dev/doc/install). You do **not** need to install Python manually: uv
   can obtain the project's pinned version.

3. Prepare dependencies from the repository root:

   ```bash
   uv sync
   go -C go-parser mod download
   ```

4. Download the two `.dem` files:

   **Google Drive:** [CS2 demo files](https://drive.google.com/drive/folders/1UgOOA8CaxJsiOhflHg3al98Yb-lQi989)

   Place the downloaded demos directly under [`data/raw/`](./data/raw/) using these
   filenames:

   ```text
   data/raw/mouz-vs-spirit-m1-dust2.dem
   data/raw/mouz-vs-spirit-m2-mirage.dem
   ```

   **Do not commit `.dem` files.** They are large (often hundreds of megabytes),
   and GitHub rejects individual files larger than 100 MiB in normal Git repositories.
   Our [`.gitignore`](./.gitignore) excludes raw demos;
   [`data/raw/.gitkeep`](./data/raw/.gitkeep) simply preserves the directory
   after cloning.

5. Generate or refresh the CSV datasets:

   ```bash
   go -C go-parser run . --input ../data/raw/mouz-vs-spirit-m1-dust2.dem
   go -C go-parser run . --input ../data/raw/mouz-vs-spirit-m2-mirage.dem
   ```

6. Open [`notebooks/parser_check.ipynb`](./notebooks/parser_check.ipynb) in VS Code
   or another Jupyter-capable editor.
   Select the project's `.venv` Python interpreter as the kernel and run the cells.

> **Already have the repository but not the large demos?** The small CSVs in
> [`data/processed/`](./data/processed/) and [`data/samples/`](./data/samples/) are
> committed to Git. You can inspect those immediately. Parsing `.dem` files with Go or
> Awpy requires downloading the raw files first.

## Prerequisites

| Tool                                                                                          | Required?                        | Notes                                                                                      |
| --------------------------------------------------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------ |
| Git                                                                                           | Yes                              | Clone and collaborate on the repository.                                                   |
| [uv](https://docs.astral.sh/uv/getting-started/installation/)                                 | Yes                              | Manages Python and project dependencies.                                                   |
| [Go](https://go.dev/doc/install)                                                              | Yes, for the Go parser           | Use a recent Go release supporting `go -C` (Go 1.20+).                                     |
| Python                                                                                        | **Managed by uv**                | `.python-version` pins **3.13.16**; `pyproject.toml` constrains Python to the 3.13 series. |
| [GNU Make](https://www.gnu.org/software/make/)                                                | Optional                         | Convenient shortcuts defined in [`Makefile`](./Makefile).                                  |
| Jupyter-capable editor                                                                        | For notebooks                    | VS Code with the Python and Jupyter extensions is one option.                              |
| [ShellCheck](https://github.com/koalaman/shellcheck) and [shfmt](https://github.com/mvdan/sh) | For `make shlint` / `make check` | Optional shell-script development tools.                                                   |

### Windows

**[WSL](https://learn.microsoft.com/en-us/windows/wsl/install) is not required.**
uv and Go run natively in Windows PowerShell, as do the direct commands throughout
this README.

For the simplest Windows setup:

1. Install [Git for Windows](https://git-scm.com/downloads/win),
   [uv](https://docs.astral.sh/uv/getting-started/installation/), and
   [Go](https://go.dev/doc/install).
2. Open **PowerShell** in the repository root.
3. Run `uv sync` and `go -C go-parser mod download`.
4. Use the direct Go commands in [Running Go directly](#running-go-directly).

If you also want to use the `make` shortcuts, use GNU Make in a Unix-like environment
such as [MSYS2](https://www.msys2.org/), or use
[WSL](https://learn.microsoft.com/en-us/windows/wsl/install) if you already prefer it.
**Git Bash alone does not guarantee that `make` is installed.** The Makefile's
cleanup and shell-lint commands use Unix utilities (`find`, `rm`), so they are not
intended for plain PowerShell.

### Linux and macOS

Install Git, uv, Go, and (optionally) GNU Make using your preferred package manager or
the tools' official installers. Then use your normal terminal from the repository root.

Check that the main tools are available:

```bash
uv --version
go version
make --version  # Only if you intend to use Make
```

## Repository layout

```text
cs2-rop/
├── Makefile                       # Setup, parsing, formatting, and cleanup
├── README.md
├── .python-version               # Python 3.13.16
├── pyproject.toml                # Python project and dependencies
├── uv.lock                       # Locked Python dependencies
├── cspell.json                   # Spell-checker configuration
├── go-parser/
│   ├── main.go                   # Go demo-to-CSV parser
│   ├── go.mod                     # Go module dependencies
│   └── go.sum
├── src/
│   └── cs2_rop/
│       └── __init__.py           # Python package
├── notebooks/
│   └── parser_check.ipynb        # Parser inspection notebook
└── data/
    ├── raw/                      # Downloaded .dem files (ignored by Git)
    │   └── .gitkeep
    ├── processed/                # Small generated CSVs (tracked in Git)
    │   ├── mouz-vs-spirit-m1-dust2_snapshots.csv
    │   └── mouz-vs-spirit-m2-mirage_snapshots.csv
    └── samples/                  # Small example CSVs (tracked in Git)
        ├── mouz-vs-spirit-m1-dust2_snapshots.csv
        └── player_snapshots.csv
```

The project deliberately keeps **large source demos outside Git** while committing the
currently small CSV datasets for easier inspection and reproducibility.

## Set up the project

Always run the commands below **from the repository root** unless otherwise indicated.

Python dependencies are managed by uv using [`pyproject.toml`](./pyproject.toml),
[`uv.lock`](./uv.lock), and [`.python-version`](./.python-version). The Go parser is a
separate Go module inside [`go-parser/`](./go-parser/); it does not require a
repository-level `go.work` file.

### With Make

```bash
make setup
```

This runs `uv sync` and `go -C go-parser mod download`. Re-running it is safe: uv
synchronizes the environment rather than rebuilding it needlessly.

### Without Make

These commands work in Bash, zsh, **and native Windows PowerShell**:

```bash
uv sync
go -C go-parser mod download
```

uv creates a local `.venv/`. Normally you do **not** need to activate it: `uv run ...`
uses the project environment automatically. The repository pins Python 3.13.16, which uv
can download if needed.

An optional [`.env`](https://dev.to/talaamm/what-is-a-env-file-and-why-should-you-use-it-599o)
file may be read by the Makefile if present. **No `.env` file is
required for the current setup.** If using one, keep private credentials out of Git;
Make's `include` expects Make-compatible variable assignments, not every possible dotenv
syntax.

## Parse demos with Go

The Go parser requires `--input` and accepts an optional `--output`. If `--output` is
omitted, the CSV is written to `data/processed/<demo-name>_snapshots.csv` relative to
the repository root. Existing output files with the same name are **overwritten**.

### Using Make targets

```bash
make parse-dust2   # Generate the Dust2 CSV
make parse-mirage  # Generate the Mirage CSV
make parse         # Generate both CSVs
```

`make all` runs `make setup` and then parses both demos. Unlike `make setup`, **parsing
requires the raw `.dem` files** to be present. Plain `make` displays help and does not
start an expensive operation.

### Running Go directly

From the repository root (also works in PowerShell):

```bash
go -C go-parser run . --input ../data/raw/mouz-vs-spirit-m1-dust2.dem
go -C go-parser run . --input ../data/raw/mouz-vs-spirit-m2-mirage.dem
```

To select an explicit output filename:

```bash
go -C go-parser run . \
  --input ../data/raw/mouz-vs-spirit-m1-dust2.dem \
  --output ../data/processed/dust2_custom.csv
```

The backslashes in the last example are **Bash/zsh line continuations**. In PowerShell,
put that entire command on one line instead.

**Why `../data/raw`, not `data/raw`?** `go -C go-parser` changes Go's working directory
to `go-parser/`. The paths passed to `--input` and `--output` are resolved from there.
You can still invoke the command while standing in the repository root.

## Explore the data in Jupyter

Open [`notebooks/parser_check.ipynb`](./notebooks/parser_check.ipynb) in VS Code
(with its **Python** and **Jupyter** extensions) or another notebook editor.

1. Run `uv sync` if you have not done so already; the project includes `ipykernel` for
   notebook use.
2. Select the interpreter/kernel from this repository's `.venv/` (the editor may display
   it simply as `.venv`).
3. Run the initialization cells, which locate the project root and configure the input
   paths.
4. Choose the desired match in the notebook configuration cell, using its **full match
   identifier**:

   ```python
   match_name = "mouz-vs-spirit-m1-dust2"
   # match_name = "mouz-vs-spirit-m2-mirage"
   ```

5. Run the Awpy section to parse the raw `.dem` and the Go parser section to inspect its
   CSV.

**Important:** Mirage is **match 2** (`m2`), whereas Dust2 is **match 1** (`m1`).
Changing only the map name while keeping `m1` would point to a nonexistent file.

The notebook looks for project-root markers such as
[`pyproject.toml`](./pyproject.toml) and [`uv.lock`](./uv.lock), so it can be started
from the repository root or the [`notebooks/`](./notebooks/) directory. Awpy parsing
may take some time and requires the downloaded `.dem` file. The CSV-inspection section
can use the committed files in [`data/processed/`](./data/processed/) without reparsing
a demo.

Before committing notebook changes, review the Git diff: executing cells can save large
results, change execution counts, and embed local filesystem paths or error tracebacks.

## Data organization and CSV columns

| Directory                              | What belongs here                             | Tracked by Git?            |
| -------------------------------------- | --------------------------------------------- | -------------------------- |
| [`data/raw/`](./data/raw/)             | Original downloaded CS2 `.dem` recordings     | **No** (except `.gitkeep`) |
| [`data/processed/`](./data/processed/) | Go-generated player snapshot CSVs             | **Yes, currently**         |
| [`data/samples/`](./data/samples/)     | Small example datasets retained for reference | **Yes**                    |

The current Go snapshot CSVs use these columns:

| Column        | Meaning                                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------------------------ |
| `tick`        | Demo tick associated with the snapshot.                                                                            |
| `round_num`   | Round number.                                                                                                      |
| `steamid`     | Player's Steam identifier; treat it as an identifier, not a quantity.                                              |
| `name`        | Player name recorded by the parser.                                                                                |
| `team`        | Numeric team/side value provided by the parser. Do not assume it permanently identifies a particular organization. |
| `alive`       | Whether the player is alive at that snapshot.                                                                      |
| `health`      | Player health at that snapshot.                                                                                    |
| `x`, `y`, `z` | Player position in CS2 game-world coordinates (not geographic coordinates or meters).                              |

These are **player snapshots**, not a complete per-event or per-tick representation.
Keep the sampling strategy and data semantics in mind when drawing statistical
conclusions. In particular, row ordering is not a reliable key: use identifiers such as
match, round, tick, and player when comparing outputs.

## Development commands

The Makefile groups common maintenance commands:

| Command              | Action                                                   | Changes files?                 |
| -------------------- | -------------------------------------------------------- | ------------------------------ |
| `make` / `make help` | Display available targets.                               | No                             |
| `make setup`         | Synchronize Python dependencies and download Go modules. | May update local environment   |
| `make parse-dust2`   | Parse Dust2 into `data/processed/`.                      | **Yes; overwrites CSV**        |
| `make parse-mirage`  | Parse Mirage into `data/processed/`.                     | **Yes; overwrites CSV**        |
| `make parse`         | Parse both demos.                                        | **Yes; overwrites CSVs**       |
| `make all`           | Run setup and parse both demos.                          | **Yes**                        |
| `make lint`          | Ruff linting/import fixes and Black formatting.          | **Yes; modifies Python files** |
| `make golint`        | Go formatting (`go fmt`) and static analysis (`go vet`). | **May format Go files**        |
| `make shlint`        | ShellCheck checks and shfmt formatting for `.sh` files.  | **May format shell scripts**   |
| `make check`         | Run Python, Go, and shell lint/format targets.           | **Yes; may modify files**      |
| `make clean`         | Remove disposable caches and notebook checkpoints.       | **Yes; deletes caches only**   |

**Note:** Despite their names, `lint` and `check` are **not read-only checks**: they
apply automatic fixes and formatting. Always inspect `git diff` afterwards. `make clean`
leaves `.venv/`, raw demos, tracked CSVs, and the notebook itself intact.

Without Make, the main Go quality commands are:

```bash
go -C go-parser fmt ./...
go -C go-parser vet ./...
```

The Python tools are run inside the uv environment, for example
`uv run ruff check . --fix` and `uv run black .`. ShellCheck and shfmt are separate
utilities; they are only needed if you're working on shell scripts or running the
full `make check` target.

## Troubleshooting

**`uv` or `go` is not recognized.** Install the tool and reopen your terminal so its
executable is on `PATH`. Check `uv --version` and `go version`.

**Python or packages are missing in the notebook.** Run `uv sync`, then select the
Python interpreter inside this repository's `.venv/` (on Windows,
`.venv/Scripts/python.exe`; on Linux/macOS, `.venv/bin/python`). Restart the notebook
kernel if necessary.

**`make` is not recognized on Windows.** Make is optional. Use the native PowerShell
commands in this README, or install GNU Make through MSYS2 or another suitable
environment.

**`FileNotFoundError` for a `.dem` file.** Download it from the Google Drive folder and
check the exact filename under `data/raw/`. Remember that Mirage is `m2`, not `m1`.

**`FileNotFoundError` for a CSV.** The committed CSVs should be under `data/processed/`.
If you need to regenerate one, run the appropriate Go parser command after obtaining its
raw demo.

**Go cannot find `go.mod`.** Run the commands from the repository root using
`go -C go-parser ...`, or change into `go-parser/` first. Running `go run .` directly
from the repository root won't select the nested Go module.

**The parser says a relative input path does not exist.** With `go -C go-parser`, paths
are relative to `go-parser/`, so use `../data/raw/...`, **not** `data/raw/...`.

**`make check` fails because `shellcheck` or `shfmt` is missing.** Those are optional
system tools. Install them if you want shell linting, or run `make lint` and
`make golint` separately.

**`git status` shows modified CSVs or notebook outputs after a run.** This may be
expected: the Go parser overwrites generated CSVs, and notebooks save cell output.
Review the diff before deciding whether to commit or discard it.

## References

- [Shared CS2 demo files on Google
  Drive](https://drive.google.com/drive/folders/1UgOOA8CaxJsiOhflHg3al98Yb-lQi989)
- [uv documentation](https://docs.astral.sh/uv/)
- [Go documentation](https://go.dev/doc/)
- [demoinfocs-golang](https://github.com/markus-wa/demoinfocs-golang)
- [Awpy](https://github.com/pnxenopoulos/awpy)
- [VS Code Jupyter
  notebooks](https://code.visualstudio.com/docs/datascience/jupyter-notebooks)
- [MSYS2 (optional Windows Make environment)](https://www.msys2.org/)
- [GNU Make](https://www.gnu.org/software/make/)
- [ShellCheck](https://github.com/koalaman/shellcheck)
- [shfmt](https://github.com/mvdan/sh)
- [WSL installation](https://learn.microsoft.com/en-us/windows/wsl/install)
- [Introduction to `.env` files](https://dev.to/talaamm/what-is-a-env-file-and-why-should-you-use-it-599o)
