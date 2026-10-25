# vim: set ft=make tw=99 nu noet ts=8 sw=8:
# =============================================================================
# CS2-ROP -- Makefile
#
# Prerequisites:
#   All platforms: uv
#   Linux/macOS:   GNU Make and standard Unix utilities
#   Windows:       GNU Make and Unix utilities via MSYS2, Git Bash, or WSL
#
# Optional development tools:
#   Python:      ruff and black (installed via uv)
#   Shell:       shellcheck and shfmt
#   Report:      latexmk and a LaTeX distribution (including pdflatex and BibTeX)
#   Analysis:    R 4.6.1 (packages via renv)
# =============================================================================

# --- Configuration ------------------------------------------------------------
# Demo paths are relative to the repository root.
RAW_DIR := data/raw
SPLIT_DIR := data/raw_split
SPLIT_MATCH := falcons-vs-natus-vincere-m3-mirage

DUST2_DEMO := $(RAW_DIR)/mouz-vs-spirit-m1-dust2.dem
MIRAGE_DEMO := $(RAW_DIR)/mouz-vs-spirit-m2-mirage.dem
PARSE_FLAGS = $(if $(filter 1,$(FORCE)),--force,)

RSCRIPT := Rscript
LATEXMK := latexmk
REPORT_DIR := reports
REPORT_TEX := $(REPORT_DIR)/data_mining_report.tex
REPORT_PDF := $(REPORT_DIR)/data_mining_report.pdf

# Load environment variables from .env file if it exists
ifneq (,$(wildcard .env))
    include .env
    export
endif

# --- Phony targets --------------------------------------------------------------
.PHONY: all help setup setup-r download-demos
.PHONY: analysis eda
.PHONY: parse parse-all parse-dust2 parse-mirage
.PHONY: pylint shlint lint
.PHONY: report clean-report clean-report-aux
.PHONY: clean check-env smoke-test

# --- Default ------------------------------------------------------------------
.DEFAULT_GOAL := help

all: setup parse
	@echo ""
	@echo "=== Full pipeline complete. ==="

help:
	@echo ""
	@echo "  make all                Run setup and extract missing baseline matches"
	@echo "  make setup              Install Python dependencies"
	@echo "  make setup-r            Install R packages from renv.lock"
	@echo "  make download-demos     Download and verify all manifest demos"
	@echo "  make parse              Extract baseline demos, skipping existing matches"
	@echo "  make parse-all          Extract missing normal matches, then the split match"
	@echo "                           Add FORCE=1 to re-extract existing matches"
	@echo "  make parse-dust2        Parse the Dust2 demo"
	@echo "  make parse-mirage       Parse the Mirage demo"
	@echo "  make analysis           Rebuild the analysis tables in data/analysis/"
	@echo "  make eda                Write the EDA figures to reports/figures/"
	@echo "  make pylint             Lint & format Python code"
	@echo "  make shlint             Lint & format shell scripts"
	@echo "  make lint               Run pylint & shlint"
	@echo "  make check-env          Verify Python environment and baseline datasets"
	@echo "  make smoke-test         Verify demos and compare parser output"
	@echo "  make report             Compile the LaTeX report"
	@echo "  make clean-report-aux   Remove LaTeX temporary files, keeping the PDF"
	@echo "  make clean-report       Remove all generated LaTeX files, including the PDF"
	@echo "  make clean              Remove generated caches and LaTeX temporary files"
	@echo "  make help               Show this message"
	@echo ""

# --- Setup -------------------------------------------------------------------
setup:
	@echo "==> Setting up Python environment"
	uv sync

setup-r:
	@echo "==> Restoring R packages with renv"
	$(RSCRIPT) -e "renv::restore(prompt = FALSE)"

download-demos:
	uv run --no-sync python -B scripts/download_demos.py

# --- Demo parsing -------------------------------------------------------------
# Match folders contain 17 Parquet tables in data/processed/.
# Existing matches, including the split match, are skipped unless FORCE=1.

parse:
	uv run --no-sync python -B scripts/extract_awpy.py \
		--input "$(DUST2_DEMO)" \
		--output data/processed \
		$(PARSE_FLAGS)
	uv run --no-sync python -B scripts/extract_awpy.py \
		--input "$(MIRAGE_DEMO)" \
		--output data/processed \
		$(PARSE_FLAGS)

parse-all:
	uv run --no-sync python -B scripts/extract_awpy.py \
		--input "$(RAW_DIR)" \
		--output data/processed \
		$(PARSE_FLAGS)
	uv run --no-sync python -B scripts/recover_split_match.py \
		--p1 "$(SPLIT_DIR)/$(SPLIT_MATCH)-p1.dem" \
		--p2 "$(SPLIT_DIR)/$(SPLIT_MATCH)-p2.dem" \
		--output data/processed \
		$(PARSE_FLAGS)

parse-dust2:
	uv run --no-sync python -B scripts/extract_awpy.py \
		--input "$(DUST2_DEMO)" \
		--output data/processed \
		$(PARSE_FLAGS)

parse-mirage:
	uv run --no-sync python -B scripts/extract_awpy.py \
		--input "$(MIRAGE_DEMO)" \
		--output data/processed \
		$(PARSE_FLAGS)

# --- Analysis -------------------------------------------------------------------
# Analysis tables are built in Python from data/processed/; EDA figures in R.

analysis:
	uv run --no-sync python -B scripts/build_analysis_tables.py

eda:
	$(RSCRIPT) R/winstreaks.R
	$(RSCRIPT) R/eda_figures.R
# --- Quarto reports (run from repo root; PDFs moved to reports/eda/) ---
	quarto render R/round_states_qmd_1.qmd --execute-dir .
	quarto render R/cs2_combined_analysis_final.qmd --execute-dir .
	mkdir -p reports/eda
	mv R/round_states_qmd_1.pdf R/cs2_combined_analysis_final.pdf reports/eda/
# ----------------

# --- Lint & format Python -----------------------------------------------------
pylint:
	@echo "==> Linting & formatting Python code"
	@uv run ruff check --select I --fix .
	@uv run black --line-length=88 --preview --enable-unstable-feature=string_processing .
	@uv run ruff check . --fix

# --- Lint & format shell scripts ----------------------------------------------
shlint:
	@echo "==> Linting & formatting shell scripts"
	@find . \( -path './.venv' -o -path './.git' \) -prune -o \
		-type f -name '*.sh' -exec shellcheck {} +
	@find . \( -path './.venv' -o -path './.git' \) -prune -o \
		-type f -name '*.sh' \
		-exec shfmt -ln=bash -s -i 2 -bn -ci -sr -w {} +

# --- Grouped dev tasks ---------------------------------------------------------
check-env:
	uv run --no-sync python -B scripts/verify.py check-env

smoke-test:
	uv run --no-sync python -B scripts/verify.py smoke-test

# Lint and also format (!) all supported languages (modifies files).
lint: pylint shlint
	@echo "==> Linting and formatting complete"

# --- Final report ------------------------------------------------------------
report:
	$(LATEXMK) -pdf -cd -interaction=nonstopmode -halt-on-error $(REPORT_TEX)
	@echo "==> Report compiled: $(REPORT_PDF)"

clean-report-aux:
	$(LATEXMK) -c -cd $(REPORT_TEX)

clean-report:
	$(LATEXMK) -C -cd $(REPORT_TEX)

# --- Clean -------------------------------------------------------------------
# Remove disposable caches and LaTeX temporary files without deleting environments, datasets, or
# the report PDF.
clean: clean-report-aux
	@echo "==> Cleaning generated caches"
	@find . \( -name .git -o -name .venv \) -prune -o \
		-type d \( \
			-name __pycache__ -o \
			-name .pytest_cache -o \
			-name .mypy_cache -o \
			-name .ruff_cache -o \
			-name .ipynb_checkpoints \
		\) -prune -exec rm -rf -- {} +
	@rm -rf htmlcov .coverage .coverage.*
	@echo "==> Cleanup complete"
