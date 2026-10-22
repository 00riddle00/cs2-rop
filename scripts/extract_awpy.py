"""Extract every awpy dataset from CS2 demos into Parquet files.

For each demo this writes <output>/<match_id>/<dataset>.parquet:

- every table in Demo.available_datasets() (rounds, kills, damages, bomb,
  grenades, fires, smokes, shots, stats, players, round_economy, chat,
  blinds, item_events)
- snapshots: all players every --seconds during live play, i.e. from
  freeze_end_tick to end_tick of each round
- header and convars as key/value tables

Every table gets a match_id column. Tables with ticks also get round_num
and in_play (freeze end <= tick <= round end). rounds gets is_overtime.

One line per demo is appended to <output>/processed_summary.csv.

Split recordings (<match>-p1.dem, <match>-p2.dem, ...) are not supported
and stop the run with an error before anything is extracted.

Usage (from the repo root):
    uv run python scripts/extract_awpy.py --input data/raw --output data/processed
"""

from __future__ import annotations

import argparse
import csv
import gc
import re
import shutil
import sys
import time
import traceback
from pathlib import Path

import polars as pl
from awpy import Demo

# Tables that describe whole rounds or the whole match, not moments.
NO_ROUND_ASSIGN = {"rounds", "round_economy", "players", "stats", "header", "convars"}

SPLIT_RE = re.compile(r"-p\d+$")

SUMMARY_NAME = "processed_summary.csv"
SUMMARY_FIELDS = [
    "match_id", "map", "rounds", "overtime_rounds", "score",
    "snapshot_rows", "seconds", "status", "warnings",
]


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--input", required=True, type=Path,
                    help="A .dem file or a directory of .dem files")
    ap.add_argument("--output", type=Path, default=Path("data/processed"),
                    help="Match folders and the summary are written here")
    ap.add_argument("--seconds", type=float, default=1.0,
                    help="Snapshot interval during live play (default 1.0)")
    ap.add_argument("--force", action="store_true",
                    help="Re-extract demos that already have output")
    return ap.parse_args()


def key_value_frame(d: dict) -> pl.DataFrame:
    return pl.DataFrame(
        {"key": [str(k) for k in d], "value": [str(v) for v in d.values()]},
        schema={"key": pl.Utf8, "value": pl.Utf8},
    )


def round_bounds(rounds: pl.DataFrame) -> pl.DataFrame:
    """Tick from which each round owns events.

    A round owns everything from its freeze-time start until the next
    round starts, so purchases and post-round events are included.
    in_play separates live play from the rest.
    """
    return (
        rounds.sort("round_num")
        .with_columns(
            # Without a start tick, a round begins one tick after the previous
            # round ends; the end tick itself belongs to the round it ends.
            _bound=pl.coalesce(
                pl.col("start_tick"),
                pl.col("official_end_tick").shift(1),
                pl.col("end_tick").shift(1) + 1,
                pl.lit(0),
            ).cast(pl.Int64),
            _freeze_end=pl.col("freeze_end_tick").cast(pl.Int64),
            _end=pl.col("end_tick").cast(pl.Int64),
        )
        .select("round_num", "_bound", "_freeze_end", "_end")
        .sort("_bound")
    )


def assign_rounds(df: pl.DataFrame, bounds: pl.DataFrame, tick_col: str) -> pl.DataFrame:
    """Add round_num and in_play by tick. Warmup ticks get null round_num."""
    out = (
        df.with_columns(_t=pl.col(tick_col).cast(pl.Int64))
        .sort("_t")
        .join_asof(bounds, left_on="_t", right_on="_bound", strategy="backward")
        .with_columns(
            in_play=(pl.col("_t") >= pl.col("_freeze_end"))
            & (pl.col("_t") <= pl.col("_end"))
        )
    )
    return out.drop("_t", "_bound", "_freeze_end", "_end")


def snapshot_ticks(rounds: pl.DataFrame, stride: int) -> pl.DataFrame:
    rows = [
        (t, r["round_num"])
        for r in rounds.iter_rows(named=True)
        if r["freeze_end_tick"] is not None
        for t in range(r["freeze_end_tick"], r["end_tick"], stride)
    ]
    return pl.DataFrame(
        rows, schema={"tick": pl.Int64, "round_num": pl.Int32}, orient="row"
    )


def score_by_team(rounds: pl.DataFrame, snaps: pl.DataFrame) -> str:
    """Round wins per team, using each side's team at freeze end."""
    if "team_clan_name" not in snaps.columns or snaps.is_empty():
        return ""
    freeze = rounds.select(
        "round_num", pl.col("freeze_end_tick").cast(pl.Int64).alias("_t")
    )
    side_team = (
        snaps.with_columns(_t=pl.col("tick").cast(pl.Int64))
        .join(freeze, on=["round_num", "_t"])
        .group_by("round_num", "side")
        .agg(team=pl.col("team_clan_name").drop_nulls().mode().first())
    )
    wins = (
        rounds.select("round_num", pl.col("winner_side").alias("side"))
        .join(side_team, on=["round_num", "side"], how="left")
        .group_by("team")
        .len()
        .sort("len", descending=True)
    )
    return "; ".join(f"{team} {n}" for team, n in wins.iter_rows())


def build_tables(
    demo: Demo, seconds: float, rounds_override: pl.DataFrame | None = None
) -> tuple[dict[str, pl.DataFrame], dict, list[str]]:
    """All tables for one demo. rounds_override replaces awpy's rounds."""
    warnings: list[str] = []
    tables: dict[str, pl.DataFrame] = {}

    names = list(Demo.available_datasets())
    try:
        demo.load(*names)
    except Exception as e:  # fall back to loading each dataset on access
        warnings.append(f"load(): {e}")
    for name in names:
        try:
            tables[name] = getattr(demo, name)
        except Exception as e:
            warnings.append(f"{name}: {e}")

    if rounds_override is not None:
        tables["rounds"] = rounds_override
    if "rounds" not in tables:
        raise RuntimeError("rounds dataset failed: " + " | ".join(warnings))

    header = dict(demo.header)
    tables["header"] = key_value_frame(header)
    try:
        convars = dict(demo.convars)
    except Exception as e:
        convars = {}
        warnings.append(f"convars: {e}")
    tables["convars"] = key_value_frame(convars)

    try:
        max_rounds = int(convars.get("mp_maxrounds", 24))
    except ValueError:
        max_rounds = 24
    rounds = tables["rounds"].with_columns(is_overtime=pl.col("round_num") > max_rounds)
    tables["rounds"] = rounds

    # Snapshots during live play, with round_num and team name attached.
    stride = max(1, round(seconds * demo.tick_rate))
    ticks = snapshot_ticks(rounds, stride)
    if ticks.is_empty():
        raise RuntimeError("no complete rounds found in this demo")
    snaps = demo.snapshots(ticks=ticks["tick"].to_list())
    snaps = snaps.with_columns(_t=pl.col("tick").cast(pl.Int64)).join(
        ticks.rename({"tick": "_t"}), on="_t", how="left"
    ).drop("_t")
    players = tables.get("players")
    if players is not None and "team_clan_name" in players.columns:
        snaps = snaps.join(
            players.select("steamid", "team_clan_name").unique("steamid"),
            on="steamid", how="left",
        )
    tables["snapshots"] = snaps

    # round_num and in_play for every table indexed by tick.
    bounds = round_bounds(rounds)
    for name, df in tables.items():
        if name in NO_ROUND_ASSIGN or name == "snapshots" or "round_num" in df.columns:
            continue
        tick_col = next((c for c in ("tick", "start_tick") if c in df.columns), None)
        if tick_col is None:
            warnings.append(f"{name}: no tick column, round_num not added")
            continue
        tables[name] = assign_rounds(df, bounds, tick_col)

    return tables, header, warnings


def write_match(tables: dict[str, pl.DataFrame], out_root: Path, match_id: str) -> None:
    # Write to a temp dir and rename, so a crash never leaves a half match.
    tmp = out_root / f".{match_id}.tmp"
    final = out_root / match_id
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    for name, df in tables.items():
        df.select(pl.lit(match_id).alias("match_id"), pl.all()).write_parquet(
            tmp / f"{name}.parquet"
        )
    shutil.rmtree(final, ignore_errors=True)
    tmp.rename(final)


def summary_row(match_id: str, tables: dict[str, pl.DataFrame], header: dict,
                warnings: list[str], t0: float) -> dict:
    rounds, snaps = tables["rounds"], tables["snapshots"]
    return {
        "match_id": match_id,
        "map": header.get("map_name", ""),
        "rounds": rounds.height,
        "overtime_rounds": int(rounds["is_overtime"].sum()),
        "score": score_by_team(rounds, snaps),
        "snapshot_rows": snaps.height,
        "seconds": f"{time.perf_counter() - t0:.1f}",
        "status": "ok",
        "warnings": " | ".join(warnings),
    }


def extract(path: Path, out_root: Path, seconds: float) -> dict:
    t0 = time.perf_counter()
    tables, header, warnings = build_tables(Demo(str(path)), seconds)
    write_match(tables, out_root, path.stem)
    return summary_row(path.stem, tables, header, warnings, t0)


def append_summary(path: Path, row: dict) -> None:
    """Add a match's line, replacing an earlier line for the same match."""
    rows = []
    if path.exists():
        with path.open(newline="") as f:
            rows = [r for r in csv.DictReader(f) if r["match_id"] != row["match_id"]]
    rows.append(row)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=SUMMARY_FIELDS)
        w.writeheader()
        w.writerows(rows)


def main() -> int:
    args = parse_args()
    demos = sorted(args.input.glob("*.dem")) if args.input.is_dir() else [args.input]
    if not demos:
        print(f"No .dem files found in {args.input}", file=sys.stderr)
        return 1

    split = [p.name for p in demos if SPLIT_RE.search(p.stem)]
    if split:
        print("Split recordings are not supported. Remove or merge these files "
              "before running:\n  " + "\n  ".join(split), file=sys.stderr)
        return 1

    args.output.mkdir(parents=True, exist_ok=True)
    summary = args.output / SUMMARY_NAME

    failed = 0
    for i, path in enumerate(demos, 1):
        prefix = f"[{i}/{len(demos)}] {path.stem}"
        if (args.output / path.stem).exists() and not args.force:
            print(f"{prefix}: already extracted, skipping")
            continue
        try:
            row = extract(path, args.output, args.seconds)
            note = f" (warnings: {row['warnings']})" if row["warnings"] else ""
            print(f"{prefix}: {row['rounds']} rounds, {row['score']}, "
                  f"{row['seconds']} s{note}")
        except Exception as e:
            failed += 1
            traceback.print_exc()
            row = {"match_id": path.stem, "status": "failed", "warnings": str(e)}
            print(f"{prefix}: FAILED ({e})")
        append_summary(summary, row)
        gc.collect()

    print(f"\nDone: {len(demos) - failed} ok, {failed} failed. Summary: {summary}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
