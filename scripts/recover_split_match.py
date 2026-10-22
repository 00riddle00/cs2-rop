"""Recover a match recorded in two demos whose first part has no round events.

awpy finds no rounds in such a part. This script rebuilds its rounds table
from the game state instead:

- round end and winner: the tick a team's score (CCSTeam m_iScore) goes up
- start of play: the latest round_freeze_end event before that end
- a score change counts as a round only if a freeze end happened since
  the previous score change, which leaves out warmup rounds

reason / reason_name stay null and start / official end ticks are left
null, so events are assigned from the previous round's end. round_economy
is rebuilt from freeze-end snapshots with buy_type null except round 1
(pistol). Part 2 is extracted normally. Both parts are written as one match
folder with a part column (0, 1); ticks are local to each part, so join on
(part, tick). Round numbers continue across parts.

Run --check first: it prints the recovered rounds and writes nothing.

Usage (from the repo root, with both files outside data/raw):
    uv run python scripts/recover_split_match.py --check \\
        --p1 data/raw_split/falcons-vs-natus-vincere-m3-mirage-p1.dem \\
        --p2 data/raw_split/falcons-vs-natus-vincere-m3-mirage-p2.dem
    uv run python scripts/recover_split_match.py \\
        --p1 ... --p2 ... --output data/processed
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import polars as pl
from awpy import Demo

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_awpy import (  # noqa: E402
    SUMMARY_NAME, append_summary, build_tables, score_by_team, summary_row,
    write_match,
)

ROUND_SCHEMA = {
    "round_num": pl.Int32, "start_tick": pl.Int32, "freeze_end_tick": pl.Int32,
    "end_tick": pl.Int32, "official_end_tick": pl.Int32, "winner": pl.Int32,
    "winner_side": pl.Utf8, "reason": pl.Int32, "reason_name": pl.Utf8,
    "is_knife_round": pl.Boolean,
}
TEAM_PROPS = ["m_iScore", "m_szTeamname", "m_szClanTeamname"]


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--p1", required=True, type=Path, help="Part without rounds")
    ap.add_argument("--p2", required=True, type=Path, help="Part awpy parses normally")
    ap.add_argument("--output", type=Path, default=Path("data/processed"))
    ap.add_argument("--match-id", help="Default: p1's name without -p1")
    ap.add_argument("--seconds", type=float, default=1.0)
    ap.add_argument("--check", action="store_true",
                    help="Only print the recovered part-1 rounds")
    return ap.parse_args()


def event_ticks(demo: Demo, name: str) -> list[int]:
    try:
        df = demo.events[name]
    except Exception:
        return []
    return sorted(int(t) for t in df["tick"].to_list())


def side_of(team_name: str | None) -> str | None:
    n = (team_name or "").strip().upper()
    if n == "TERRORIST":
        return "terrorist"
    if n in ("CT", "COUNTER-TERRORIST", "COUNTERTERRORIST"):
        return "counter-terrorist"
    return None


def recover_rounds(
    demo: Demo,
) -> tuple[pl.DataFrame, pl.DataFrame, pl.DataFrame, list[str]]:
    """Rounds from team score changes.

    Returns the rounds, the winning clan per round, every score change
    found (with whether it was kept), and notes for the check output.
    """
    notes = []
    freeze_ends = event_ticks(demo, "round_freeze_end")
    notes.append(f"begin_new_match at ticks {event_ticks(demo, 'begin_new_match')}")
    notes.append(f"{len(freeze_ends)} round_freeze_end events")

    teams = demo.ticks(TEAM_PROPS, players_only=False)
    missing = [c for c in TEAM_PROPS if c not in teams.columns]
    if missing:
        raise RuntimeError(f"team props missing: {missing}; columns: {teams.columns}")
    notes.append("team names seen: "
                 f"{teams['m_szTeamname'].drop_nulls().unique().to_list()}")

    # Players also have m_iScore (scoreboard points); keep the two teams only.
    ends = (
        teams.filter(
            pl.col("m_iScore").is_not_null()
            & pl.col("m_szTeamname").str.strip_chars().str.to_uppercase()
            .is_in(["TERRORIST", "CT", "COUNTER-TERRORIST", "COUNTERTERRORIST"])
        )
        .sort("entity_id", "entity_serial", "tick")
        .with_columns(
            step=pl.col("m_iScore").diff().over("entity_id", "entity_serial")
        )
        .filter(pl.col("step") == 1)
        .sort("tick")
    )

    rows, clans, changes = [], [], []
    prev_end = -1
    for e in ends.iter_rows(named=True):
        end = int(e["tick"])
        side = side_of(e["m_szTeamname"])
        fe = max((f for f in freeze_ends if prev_end < f <= end), default=None)
        changes.append({"tick": end, "team": e["m_szTeamname"],
                        "clan": e["m_szClanTeamname"], "score_after": e["m_iScore"],
                        "freeze_end_tick": fe, "kept": fe is not None})
        prev_end = end
        if fe is None:
            continue
        i = len(rows) + 1
        rows.append({
            "round_num": i, "start_tick": None, "freeze_end_tick": fe,
            "end_tick": end, "official_end_tick": None,
            "winner": {"terrorist": 2, "counter-terrorist": 3}.get(side),
            "winner_side": side, "reason": None, "reason_name": None,
            "is_knife_round": False,
        })
        clans.append({"round_num": i, "winner_clan": e["m_szClanTeamname"],
                      "score_after": e["m_iScore"]})

    rounds = pl.DataFrame(rows, schema=ROUND_SCHEMA)
    clans = pl.DataFrame(clans, schema={"round_num": pl.Int32, "winner_clan": pl.Utf8,
                                        "score_after": pl.Int64})
    changes = pl.DataFrame(changes, schema={
        "tick": pl.Int64, "team": pl.Utf8, "clan": pl.Utf8, "score_after": pl.Int64,
        "freeze_end_tick": pl.Int64, "kept": pl.Boolean})
    if rounds["winner_side"].is_null().any():
        notes.append("WARNING: some winners have an unknown team name")
    return rounds, clans, changes, notes


def economy_from_snapshots(rounds: pl.DataFrame, snaps: pl.DataFrame) -> pl.DataFrame:
    freeze = rounds.select("round_num", pl.col("freeze_end_tick").cast(pl.Int64).alias("_t"))
    return (
        snaps.with_columns(_t=pl.col("tick").cast(pl.Int64))
        .join(freeze, on=["round_num", "_t"])
        .group_by("round_num", "side")
        .agg(equipment_value=pl.col("equipment_value").sum().cast(pl.Int32),
             n_players=pl.len().cast(pl.Int32))
        .with_columns(buy_type=pl.when(pl.col("round_num") == 1)
                      .then(pl.lit("pistol")).otherwise(pl.lit(None, pl.Utf8)))
        .select("round_num", "side", "equipment_value", "buy_type", "n_players")
        .sort("round_num", "side")
    )


def merge_parts(parts: list[dict[str, pl.DataFrame]]) -> dict[str, pl.DataFrame]:
    names = dict.fromkeys(n for p in parts for n in p)
    merged = {}
    for name in names:
        frames = [
            p[name].with_columns(pl.lit(i, pl.UInt32).alias("part"))
            for i, p in enumerate(parts) if name in p
        ]
        merged[name] = pl.concat(frames, how="diagonal_relaxed")
    return merged


def main() -> int:
    args = parse_args()
    t0 = time.perf_counter()
    match_id = args.match_id or args.p1.stem.removesuffix("-p1")

    demo1 = Demo(str(args.p1))
    rounds1, clans, changes, notes = recover_rounds(demo1)
    for n in notes:
        print(n)
    print("All score changes:")
    print(changes)
    if rounds1.is_empty():
        print("No rounds recovered.", file=sys.stderr)
        return 1
    print("Recovered rounds:")
    print(rounds1.join(clans, on="round_num")
          .select("round_num", "freeze_end_tick", "end_tick", "winner_side",
                  "winner_clan", "score_after"))
    print(clans.group_by("winner_clan").len().sort("len", descending=True))
    if args.check:
        return 0

    p1, header, warn1 = build_tables(demo1, args.seconds, rounds_override=rounds1)
    if p1.get("round_economy") is None or p1["round_economy"].is_empty():
        p1["round_economy"] = economy_from_snapshots(p1["rounds"], p1["snapshots"])
    p2, _, warn2 = build_tables(Demo(str(args.p2)), args.seconds)

    first_p2 = p2["rounds"]["round_num"].min()
    if first_p2 != rounds1.height + 1:
        print(f"WARNING: part 1 has {rounds1.height} rounds but part 2 starts "
              f"at round {first_p2}", file=sys.stderr)

    tables = merge_parts([p1, p2])
    write_match(tables, args.output, match_id)
    warnings = ["split recording, part 1 rounds recovered from team scores"]
    warnings += [f"p1 {w}" for w in warn1] + [f"p2 {w}" for w in warn2]
    row = summary_row(match_id, tables, header, warnings, t0)
    append_summary(args.output / SUMMARY_NAME, row)
    print(f"{match_id}: {row['rounds']} rounds, {row['score']}, {row['seconds']} s")
    print("warnings:", row["warnings"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
