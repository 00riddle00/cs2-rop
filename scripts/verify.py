"""Verify the Python environment and reproduce the two baseline Awpy matches."""

import argparse
import hashlib
import importlib.metadata
import json
import re
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATCHES = ("mouz-vs-spirit-m1-dust2", "mouz-vs-spirit-m2-mirage")
TABLES = (
    "rounds",
    "kills",
    "damages",
    "bomb",
    "grenades",
    "fires",
    "smokes",
    "shots",
    "stats",
    "players",
    "round_economy",
    "chat",
    "blinds",
    "item_events",
    "header",
    "convars",
    "snapshots",
)


class CheckError(Exception):
    """An actionable verification failure."""


def report(message: str) -> None:
    print(message, flush=True)


def run(args: list[str]) -> None:
    report(f"Running: {subprocess.list2cmdline(args)}")
    try:
        subprocess.run(args, cwd=ROOT, check=True)
    except FileNotFoundError as exc:
        raise CheckError(f"Command not found: {args[0]}. Check PATH.") from exc
    except subprocess.CalledProcessError as exc:
        raise CheckError(f"Command failed (exit {exc.returncode}): {args[0]}") from exc


def read_match(folder: Path, match: str) -> dict:
    """Require all 17 readable tables; empty event tables are legitimate."""
    import polars as pl

    expected = {f"{table}.parquet" for table in TABLES}
    actual = {path.name for path in folder.glob("*.parquet")}
    if actual != expected:
        raise CheckError(
            f"{folder}: unexpected table set; "
            f"missing={sorted(expected - actual)}, extra={sorted(actual - expected)}"
        )
    tables = {}
    for table in TABLES:
        path = folder / f"{table}.parquet"
        try:
            frame = pl.read_parquet(path)
        except pl.exceptions.PolarsError as exc:
            raise CheckError(f"{path}: invalid Parquet: {exc}") from exc
        if "match_id" not in frame.columns:
            raise CheckError(f"{path}: missing match_id column")
        if frame.height and frame["match_id"].unique().to_list() != [match]:
            raise CheckError(f"{path}: match_id must be {match!r} on every row")
        if table in {"rounds", "snapshots", "header"} and frame.is_empty():
            raise CheckError(f"{path}: required table is empty")
        tables[table] = frame
    report(f"Valid match: {match} ({len(tables)} Parquet tables)")
    return tables


def check_env() -> dict:
    expected = (ROOT / ".python-version").read_text(encoding="utf-8").strip()
    actual = ".".join(map(str, sys.version_info[:3]))
    if Path(sys.prefix).resolve() != (ROOT / ".venv").resolve():
        raise CheckError(
            "Use the project .venv: run uv sync, then "
            "uv run --no-sync python -B scripts/verify.py check-env"
        )
    if actual != expected:
        raise CheckError(
            f"Python {actual} does not match .python-version ({expected}). Run uv sync."
        )
    report(f"Python {actual}: {sys.executable}")
    run(["uv", "pip", "check", "--python", sys.executable])
    project = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    requirement = next(
        dep for dep in project["project"]["dependencies"] if dep.startswith("awpy==")
    )
    version = importlib.metadata.version("awpy")
    if version != requirement.removeprefix("awpy=="):
        raise CheckError(
            f"Installed awpy {version} does not match {requirement}. Run uv sync."
        )
    run(
        [
            sys.executable,
            "-B",
            "-c",
            (
                "from awpy import Demo; import polars, pandas, pyarrow; "
                "print('Awpy, Polars, pandas, and PyArrow imports: OK')"
            ),
        ]
    )
    report(f"Awpy {version}: matches pyproject.toml")

    references = {}
    for match in MATCHES:
        demo = ROOT / "data" / "raw" / f"{match}.dem"
        with demo.open("rb") as stream:
            if stream.read(8) != b"PBDEMS2\x00" or demo.stat().st_size <= 8:
                raise CheckError(
                    f"{demo}: nonempty CS2 demo with PBDEMS2 header required"
                )
        report(f"Demo present with CS2 header: {demo.name}")
        references[match] = read_match(ROOT / "data" / "processed" / match, match)
    return references


def check_references() -> None:
    # Require unchanged committed references even though table comparison ignores
    # row order and Parquet encoding. Local regeneration is not a new baseline.
    paths = [f"data/processed/{match}" for match in MATCHES]
    try:
        result = subprocess.run(
            ["git", "diff", "--quiet", "HEAD", "--", *paths],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as exc:
        raise CheckError(
            "smoke-test requires Git on PATH to verify references."
        ) from exc
    if result.returncode == 1:
        raise CheckError(
            "Reference match folders differ from HEAD (staged or unstaged changes). "
            "Review and commit intentional reference updates, or restore the "
            "committed references, before running smoke-test."
        )
    if result.returncode != 0:
        raise CheckError(
            "Could not verify reference matches against Git HEAD "
            f"(exit {result.returncode}): {result.stderr.strip()}"
        )
    report("Reference match folders match Git HEAD")


def compare_tables(match: str, actual: dict, expected: dict) -> None:
    from polars.testing import assert_frame_equal

    for table in TABLES:
        try:
            assert_frame_equal(
                actual[table], expected[table], check_row_order=False, check_exact=True
            )
        except AssertionError as exc:
            raise CheckError(f"{match}/{table}.parquet: {exc}") from exc
        report(f"MATCH {match}/{table}.parquet: {actual[table].height} rows")


def smoke_test(references: dict, work: Path) -> None:
    check_references()
    checksums = json.loads(
        (ROOT / "data" / "raw_checksums.json").read_text(encoding="utf-8")
    )
    if not isinstance(checksums, dict):
        raise CheckError("data/raw_checksums.json must contain demo records")
    # Check both inputs before extracting either demo.
    for match in MATCHES:
        demo = ROOT / "data" / "raw" / f"{match}.dem"
        entry = checksums.get(demo.name)
        expected = entry.get("sha256") if isinstance(entry, dict) else None
        if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise CheckError(
                f"Missing or invalid SHA-256 for {demo.name} in data/raw_checksums.json"
            )
        with demo.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != expected:
            raise CheckError(
                f"{demo}: SHA-256 mismatch\nExpected: {expected}\nActual:   {actual}"
            )
        report(f"SHA-256 verified: {demo.name}")

    for match in MATCHES:
        run(
            [
                sys.executable,
                "-B",
                str(ROOT / "scripts" / "extract_awpy.py"),
                "--input",
                str(ROOT / "data" / "raw" / f"{match}.dem"),
                "--output",
                str(work),
                "--seconds",
                "1",
            ]
        )
        actual = read_match(work / match, match)
        compare_tables(match, actual, references[match])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check-env", "smoke-test"))
    args = parser.parse_args()
    try:
        references = check_env()
        report("Environment and baseline matches: OK")
        if args.command == "smoke-test":
            with tempfile.TemporaryDirectory(prefix="cs2-rop-") as directory:
                smoke_test(references, Path(directory).resolve())
        report(f"{args.command}: PASS")
        return 0
    except (CheckError, OSError, ValueError, ImportError) as exc:
        print(f"{args.command}: FAIL: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print(f"{args.command}: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
