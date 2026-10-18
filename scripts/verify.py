"""Cross-platform environment and parser checks; never write reference datasets."""

import argparse
import csv
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATCHES = ("mouz-vs-spirit-m1-dust2", "mouz-vs-spirit-m2-mirage")
COLUMNS = (
    "tick",
    "round_num",
    "steamid",
    "name",
    "team",
    "alive",
    "health",
    "x",
    "y",
    "z",
)


class CheckError(Exception):
    """An actionable verification failure."""


def report(message: str) -> None:
    print(message, flush=True)


def run(args: list[str], *, cwd: Path = ROOT, env=None) -> None:
    report(f"Running: {subprocess.list2cmdline(args)}")
    try:
        subprocess.run(args, cwd=cwd, env=env, check=True)
    except FileNotFoundError as exc:
        raise CheckError(f"Command not found: {args[0]}. Check PATH.") from exc
    except subprocess.CalledProcessError as exc:
        raise CheckError(f"Command failed (exit {exc.returncode}): {args[0]}") from exc


def read_csv(path: Path) -> dict:
    """Validate and index exact field values without depending on row order."""
    rows = {}
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.reader(stream, strict=True)
        if next(reader, None) != list(COLUMNS):
            raise CheckError(f"{path}: expected CSV columns {', '.join(COLUMNS)}")
        for line, values in enumerate(reader, start=2):
            try:
                if len(values) != len(COLUMNS) or any(v == "" for v in values):
                    raise ValueError("expected ten nonempty fields")
                row = dict(zip(COLUMNS, values))
                for field in ("tick", "round_num", "steamid", "team", "health"):
                    if not row[field].isascii() or not row[field].isdigit():
                        raise ValueError(f"{field} must be a nonnegative integer")
                if int(row["round_num"]) < 1 or int(row["steamid"]) < 1:
                    raise ValueError("round_num and steamid must be positive")
                if row["team"] not in ("2", "3"):
                    raise ValueError("team must be 2 or 3")
                if row["alive"] not in ("true", "false"):
                    raise ValueError("alive must be true or false")
                for field in ("x", "y", "z"):
                    if not math.isfinite(float(row[field])):
                        raise ValueError(f"{field} must be finite")
                key = (int(row["round_num"]), int(row["tick"]), row["steamid"])
                if key in rows:
                    raise ValueError(f"duplicate key {key}")
                rows[key] = tuple(values)
            except ValueError as exc:
                raise CheckError(f"{path}, line {line}: {exc}") from exc
    if not rows:
        raise CheckError(f"{path}: CSV has no data rows")
    report(f"Valid CSV: {path.name} ({len(rows)} rows)")
    return rows


def check_env(work: Path) -> tuple[Path, dict]:
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
    # Import native extensions too: installed metadata alone cannot prove usability.
    env = dict(os.environ, MPLCONFIGDIR=str(work / "matplotlib"))
    run(
        [
            sys.executable,
            "-B",
            "-c",
            "from awpy import Demo; import demoparser2, pandas, polars, pyarrow; "
            "polars.DataFrame({'value': [1]}).to_pandas(); "
            "print('Dependency imports and dataframe conversion: OK')",
        ],
        env=env,
    )

    if not shutil.which("go"):
        raise CheckError(
            "Go is missing from PATH. Install the version required by go-parser/go.mod."
        )
    run(["go", "version"])
    binary = work / ("parser.exe" if os.name == "nt" else "parser")
    run(
        ["go", "build", "-mod=readonly", "-o", str(binary), "."], cwd=ROOT / "go-parser"
    )
    report("Go compilation: OK")

    references = {}
    for match in MATCHES:
        demo = ROOT / "data" / "raw" / f"{match}.dem"
        with demo.open("rb") as stream:
            if stream.read(8) != b"PBDEMS2\x00" or demo.stat().st_size <= 8:
                raise CheckError(
                    f"{demo}: not a nonempty CS2 demo (PBDEMS2 header required)"
                )
        report(f"Demo present with CS2 header: {demo.name}")
        references[match] = read_csv(
            ROOT / "data" / "processed" / f"{match}_snapshots.csv"
        )
    return binary, references


def check_references() -> None:
    paths = [f"data/processed/{match}_snapshots.csv" for match in MATCHES]
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
            "Reference CSVs differ from HEAD (staged or unstaged changes). "
            "Review and commit intentional reference updates, or restore the "
            "committed references, before running smoke-test."
        )
    if result.returncode != 0:
        raise CheckError(
            f"Could not verify reference CSVs against Git HEAD "
            f"(exit {result.returncode}): {result.stderr.strip()}"
        )
    report("Reference CSVs match Git HEAD")


def smoke_test(binary: Path, references: dict, work: Path) -> None:
    check_references()
    checksums = json.loads(
        (ROOT / "data" / "raw_checksums.json").read_text(encoding="utf-8")
    )
    if not isinstance(checksums, dict):
        raise CheckError("data/raw_checksums.json must contain demo records")
    # Check both inputs before running either demo through the parser.
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
        generated = work / f"{match}_snapshots.csv"
        run(
            [
                str(binary),
                "--input",
                str(ROOT / "data" / "raw" / f"{match}.dem"),
                "--output",
                str(generated),
            ],
            cwd=ROOT / "go-parser",
        )
        actual = read_csv(generated)
        expected = references[match]
        missing = expected.keys() - actual.keys()
        extra = actual.keys() - expected.keys()
        if missing or extra:
            raise CheckError(
                f"{match}: CSV keys differ: "
                f"{len(missing)} missing, {len(extra)} extra; "
                f"first missing={min(missing) if missing else None}, "
                f"first extra={min(extra) if extra else None}"
            )
        for key in sorted(expected):
            if actual[key] != expected[key]:
                differences = [
                    f"{column}: expected {old!r}, got {new!r}"
                    for column, old, new in zip(COLUMNS, expected[key], actual[key])
                    if old != new
                ]
                raise CheckError(
                    f"{match}: CSV mismatch at {key}: " + "; ".join(differences)
                )
        report(f"Reference comparison: {match}: all {len(actual)} rows match")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check-env", "smoke-test"))
    args = parser.parse_args()
    try:
        with tempfile.TemporaryDirectory(prefix="cs2-rop-") as directory:
            work = Path(directory).resolve()
            binary, references = check_env(work)
            report("Environment and datasets: OK")
            if args.command == "smoke-test":
                smoke_test(binary, references, work)
        report(f"{args.command}: PASS")
        return 0
    except (CheckError, OSError, ValueError, csv.Error) as exc:
        print(f"{args.command}: FAIL: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print(f"{args.command}: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
