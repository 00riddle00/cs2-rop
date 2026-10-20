"""Run the Go snapshot parser, skipping existing CSVs unless --force is given."""

import argparse
import csv
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from verify import CheckError, read_csv

ROOT = Path(__file__).resolve().parents[1]


def report(message: str) -> None:
    print(message, flush=True)


def process_demo(binary: Path, demo: Path, output: Path, force: bool) -> bool:
    """Publish a validated CSV; return False if another run created the output."""
    with tempfile.TemporaryDirectory(prefix=".parse-", dir=output.parent) as directory:
        temporary = Path(directory) / output.name
        subprocess.run(
            [str(binary), "--input", str(demo), "--output", str(temporary)],
            check=True,
        )
        read_csv(temporary)
        if force:
            os.replace(temporary, output)
        else:
            # Same-filesystem hard links publish atomically without replacing a file.
            # TemporaryDirectory then removes the temporary name, keeping the CSV.
            try:
                os.link(temporary, output)
            except FileExistsError:
                return False
    return True


def parse_demos(demos: list[Path], force: bool) -> int:
    processed = skipped = failed = 0
    output_dir = ROOT / "data" / "processed"
    pending = []
    for demo in demos:
        output = output_dir / f"{demo.stem}_snapshots.csv"
        if not demo.is_file() or demo.suffix.lower() != ".dem":
            report(f"FAILED {demo}: expected an existing .dem file")
            failed += 1
        elif not force and os.path.lexists(output):
            report(f"SKIPPED {demo.name}: {output.name} already exists")
            skipped += 1
        else:
            pending.append((demo, output))

    attempted = 0
    batch_failed = False
    if pending:
        if force:
            report(
                "FORCE enabled: existing selected CSVs, including tracked "
                "references, may be replaced."
            )
        try:
            output_dir.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory(prefix="cs2-rop-parser-") as directory:
                binary = Path(directory).resolve() / (
                    "parser.exe" if os.name == "nt" else "parser"
                )
                report("Building Go parser once for this batch")
                subprocess.run(
                    ["go", "build", "-mod=readonly", "-o", str(binary), "."],
                    cwd=ROOT / "go-parser",
                    check=True,
                )
                for demo, output in pending:
                    attempted += 1
                    report(f"PARSING {demo.name}")
                    try:
                        if process_demo(binary, demo, output, force):
                            report(f"PROCESSED {demo.name} -> {output.name}")
                            processed += 1
                        else:
                            report(
                                f"SKIPPED {demo.name}: output created by another run"
                            )
                            skipped += 1
                    except (
                        OSError,
                        subprocess.CalledProcessError,
                        CheckError,
                        csv.Error,
                        ValueError,
                    ) as exc:
                        report(f"FAILED {demo.name}: {exc}")
                        failed += 1
        except (OSError, subprocess.CalledProcessError) as exc:
            report(
                f"Batch failed: {exc}. Check Go installation and output permissions."
            )
            failed += len(pending) - attempted
            batch_failed = True

    report(f"Summary: {processed} processed, {skipped} skipped, {failed} failed")
    return 1 if failed or batch_failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "demos", nargs="*", type=Path, help="Paths to selected .dem files"
    )
    parser.add_argument(
        "--all", action="store_true", help="Discover .dem files in data/raw"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace existing CSVs, including tracked references",
    )
    args = parser.parse_args()
    if args.all == bool(args.demos):
        parser.error("Specify either --all or one or more demo paths")
    demos = sorted(
        set(
            path.absolute()
            for path in (
                (ROOT / "data" / "raw").glob("*.dem") if args.all else args.demos
            )
        )
    )
    if not demos:
        parser.error(
            "No .dem files found in data/raw; run make download-demos or add demos"
        )
    try:
        return parse_demos(demos, args.force)
    except KeyboardInterrupt:
        print("Parsing interrupted; temporary files cleaned up.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
