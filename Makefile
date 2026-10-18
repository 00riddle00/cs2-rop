# vim: set ft=make tw=99 nu noet ts=8 sw=8:
# =============================================================================
# CS2-ROP -- Makefile
#
# Prerequisites:
#   All platforms: uv and Go
#   Linux/macOS:   GNU Make and standard Unix utilities
#   Windows:       GNU Make and Unix utilities via MSYS2, Git Bash, or WSL
#
# Optional development tools:
#   Python:      ruff and black (installed via uv)
#   Shell:       shellcheck and shfmt
# =============================================================================

# --- Configuration ------------------------------------------------------------
# Paths passed to Go are relative to go-parser/ because of go -C.
GO_PARSER := go-parser
RAW_DIR := ../data/raw

DUST2_DEMO := $(RAW_DIR)/mouz-vs-spirit-m1-dust2.dem
MIRAGE_DEMO := $(RAW_DIR)/mouz-vs-spirit-m2-mirage.dem

# Load environment variables from .env file if it exists
ifneq (,$(wildcard .env))
    include .env
    export
endif

# --- Phony targets --------------------------------------------------------------
.PHONY: all help setup download-demos
.PHONY: parse parse-dust2 parse-mirage
.PHONY: pylint golint shlint lint
.PHONY: clean check-env smoke-test

# --- Default ------------------------------------------------------------------
.DEFAULT_GOAL := help

all: setup parse
	@echo ""
	@echo "=== Full pipeline complete. ==="

help:
	@echo ""
	@echo "  make all            Run setup and parse both demos"
	@echo "  make setup          Install Python and Go dependencies"
	@echo "  make download-demos Download and verify all manifest demos"
	@echo "  make parse          Parse both demos"
	@echo "  make parse-dust2    Parse the Dust2 demo"
	@echo "  make parse-mirage   Parse the Mirage demo"
	@echo "  make pylint         Lint & format Python code"
	@echo "  make golint         Lint & format Go code"
	@echo "  make shlint         Lint & format shell scripts"
	@echo "  make lint           Run pylint & golint & shlint"
	@echo "  make check-env      Verify environment, Go build, and datasets"
	@echo "  make smoke-test     Verify demos and compare parser output"
	@echo "  make clean          Remove generated caches"
	@echo "  make help           Show this message"
	@echo ""

# --- Setup -------------------------------------------------------------------
setup:
	@echo "==> Setting up Python environment"
	uv sync
	@echo "==> Downloading Go dependencies"
	go -C $(GO_PARSER) mod download

download-demos:
	uv run --no-sync python -B scripts/download_demos.py

# --- Demo parsing -------------------------------------------------------------
# Generated CSVs are saved to data/processed/.
# Existing output files with matching names will be overwritten.

parse: parse-dust2 parse-mirage

parse-dust2:
	go -C $(GO_PARSER) run . --input $(DUST2_DEMO)

parse-mirage:
	go -C $(GO_PARSER) run . --input $(MIRAGE_DEMO)

# --- Lint & format Python -----------------------------------------------------
pylint:
	@echo "==> Linting & formatting Python code"
	@uv run ruff check . --fix
	@uv run ruff check --select I --fix .
	@uv run ruff format .
	@uv run black --line-length=88 --preview --enable-unstable-feature=string_processing .

# --- Lint & format Go ---------------------------------------------------------
golint:
	@echo "==> Linting & formatting Go code"
	@go -C $(GO_PARSER) fmt ./...
	@go -C $(GO_PARSER) vet ./...

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
lint: pylint golint shlint
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
