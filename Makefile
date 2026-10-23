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
# =============================================================================

# --- Configuration ------------------------------------------------------------
# Demo paths are relative to the repository root.
RAW_DIR := data/raw
SPLIT_DIR := data/raw_split
SPLIT_MATCH := falcons-vs-natus-vincere-m3-mirage

DUST2_DEMO := $(RAW_DIR)/mouz-vs-spirit-m1-dust2.dem
MIRAGE_DEMO := $(RAW_DIR)/mouz-vs-spirit-m2-mirage.dem
PARSE_FLAGS = $(if $(filter 1,$(FORCE)),--force,)

# Load environment variables from .env file if it exists
ifneq (,$(wildcard .env))
    include .env
    export
endif

# --- Phony targets --------------------------------------------------------------
.PHONY: all help setup download-demos
.PHONY: parse parse-all parse-dust2 parse-mirage
.PHONY: pylint shlint lint
.PHONY: clean check-env smoke-test

# --- Default ------------------------------------------------------------------
.DEFAULT_GOAL := help

all: setup parse
	@echo ""
	@echo "=== Full pipeline complete. ==="

help:
	@echo ""
	@echo "  make all            Run setup and extract missing baseline matches"
	@echo "  make setup          Install Python dependencies"
	@echo "  make download-demos Download and verify all manifest demos"
	@echo "  make parse          Extract baseline demos, skipping existing matches"
	@echo "  make parse-all      Extract normal demos, then rebuild the split match"
	@echo "                       Add FORCE=1 to re-extract existing normal matches"
	@echo "  make parse-dust2    Parse the Dust2 demo"
	@echo "  make parse-mirage   Parse the Mirage demo"
	@echo "  make pylint         Lint & format Python code"
	@echo "  make shlint         Lint & format shell scripts"
	@echo "  make lint           Run pylint & shlint"
	@echo "  make check-env      Verify Python environment and baseline datasets"
	@echo "  make smoke-test     Verify demos and compare parser output"
	@echo "  make clean          Remove generated caches"
	@echo "  make help           Show this message"
	@echo ""

# --- Setup -------------------------------------------------------------------
setup:
	@echo "==> Setting up Python environment"
	uv sync

download-demos:
	uv run --no-sync python -B scripts/download_demos.py

# --- Demo parsing -------------------------------------------------------------
# Match folders contain 17 Parquet tables in data/processed/.
# Normal matches are skipped unless FORCE=1; split recovery always rewrites.

parse:
	uv run --no-sync python -B scripts/extract_awpy.py --input "$(DUST2_DEMO)" --output data/processed $(PARSE_FLAGS)
	uv run --no-sync python -B scripts/extract_awpy.py --input "$(MIRAGE_DEMO)" --output data/processed $(PARSE_FLAGS)

parse-all:
	uv run --no-sync python -B scripts/extract_awpy.py --input "$(RAW_DIR)" --output data/processed $(PARSE_FLAGS)
	uv run --no-sync python -B scripts/recover_split_match.py --p1 "$(SPLIT_DIR)/$(SPLIT_MATCH)-p1.dem" --p2 "$(SPLIT_DIR)/$(SPLIT_MATCH)-p2.dem" --output data/processed

parse-dust2:
	uv run --no-sync python -B scripts/extract_awpy.py --input "$(DUST2_DEMO)" --output data/processed $(PARSE_FLAGS)

parse-mirage:
	uv run --no-sync python -B scripts/extract_awpy.py --input "$(MIRAGE_DEMO)" --output data/processed $(PARSE_FLAGS)

# --- Lint & format Python -----------------------------------------------------
pylint:
	@echo "==> Linting & formatting Python code"
	@uv run ruff check . --fix
	@uv run ruff check --select I --fix .
	@uv run ruff format .
	@uv run black --line-length=88 --preview --enable-unstable-feature=string_processing .

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

# --- Clean -------------------------------------------------------------------
# Remove disposable caches without deleting environments or datasets.
clean:
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
