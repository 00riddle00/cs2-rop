"""Build analysis-ready tables from the processed awpy data.

Reads every match folder in --input (default data/processed) and writes to
--output (default data/analysis):

- rounds.parquet / rounds.csv: one row per round of every match
- round_states.parquet / round_states.csv: one row per snapshot tick of
  live play (every second), with the state of both sides at that moment

Both tables are team-level; no Steam IDs are included. Team names are
normalised (e.g. "Team Vitality" and "Vitality" both become "Vitality").

Columns that describe how a round ended are labels, not features:
winner_side, winner_team, ct_win and reason_name. The same holds for
round_duration_s and anything else computed over the whole round.

Notes on the data:
- part is 0 for every match except the split recording
  falcons-vs-natus-vincere-m3-mirage (0 = first half, 1 = second half);
  ticks are only unique within (match_id, part).
- reason_name is empty for rounds 1-12 of that match (recovered rounds).
- Alive means health > 0. Dead players are left out of every per-side
  sum in round_states.

Usage (from the repo root):
    uv run python scripts/build_analysis_tables.py
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import polars as pl

CT, T = "counter-terrorist", "terrorist"
SIDE_PREFIX = {CT: "ct", T: "t"}

# Observed clan-name variants of each team.
TEAM_VARIANTS = {
    "9z": ["9z Globant", "9zGlobant", "9z"],
    "Aurora": ["Aurora Gaming", "Aurora"],
    "FaZe": ["FaZe Clan", "FaZe"],
    "FURIA": ["FURIA"],
    "FUT": ["FUT Esports", "FUT"],
    "G2": ["G2 Esports", "G2.Esports", "G2"],
    "Legacy": ["LEGACY", "Legacy"],
    "MOUZ": ["MOUZ"],
    "NAVI": ["Natus Vincere"],
    "Falcons": ["Team Falcons", "Falcons"],
    "Spirit": ["Team Spirit", "Spirit"],
    "Vitality": ["Team Vitality", "Vitality"],
}
# Clan name as found in the demo -> one name per team.
TEAM_ALIASES = {v: team for team, names in TEAM_VARIANTS.items() for v in names}

RIFLES = ["ak47", "m4a1", "m4a1_silencer", "famas", "galilar", "aug", "sg556"]
SMGS = ["mac10", "mp9", "mp7", "mp5sd", "ump45", "p90", "bizon"]


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--input", type=Path, default=Path("data/processed"))
    ap.add_argument("--output", type=Path, default=Path("data/analysis"))
    ap.add_argument("--no-csv", action="store_true", help="Write Parquet only")
    return ap.parse_args()


def read(match_dir: Path, table: str) -> pl.DataFrame:
    """Read one table and make sure it has a part column."""
    df = pl.read_parquet(match_dir / f"{table}.parquet")
    if "part" not in df.columns:
        df = df.with_columns(part=pl.lit(0, pl.UInt32))
    return df.with_columns(pl.col("part").cast(pl.UInt32))


def kv(df: pl.DataFrame) -> dict[str, str]:
    """Key/value table (header, convars) as a dict; first part wins."""
    out: dict[str, str] = {}
    for key, value in df.sort("part").select("key", "value").iter_rows():
        out.setdefault(key, value)
    return out


def number(d: dict[str, str], key: str, default: float) -> float:
    try:
        return float(d[key])
    except (KeyError, ValueError):
        return default


def side_teams(snaps: pl.DataFrame) -> pl.DataFrame:
    """Team name on each side per round, from the first snapshot tick."""
    first = snaps.group_by("part", "round_num").agg(first_tick=pl.col("tick").min())
    teams = (
        snaps.join(first, on=["part", "round_num"])
        .filter((pl.col("tick") == pl.col("first_tick")) & (pl.col("health") > 0))
        .drop_nulls("team_clan_name")
        .group_by("part", "round_num", "side")
        .agg(team=pl.col("team_clan_name").mode().first())
        .with_columns(pl.col("team").replace(TEAM_ALIASES))
    )
    return (
        teams.filter(pl.col("side") == CT)
        .select("part", "round_num", ct_team="team")
        .join(
            teams.filter(pl.col("side") == T).select(
                "part", "round_num", t_team="team"
            ),
            on=["part", "round_num"],
            how="full",
            coalesce=True,
        )
    )


def build_rounds(match_id: str, d: Path) -> tuple[pl.DataFrame, dict]:
    header, convars = kv(read(d, "header")), kv(read(d, "convars"))
    playback_ticks = number(header, "playback_ticks", 0)
    playback_time = number(header, "playback_time", 0)
    tick_rate = round(playback_ticks / playback_time) if playback_time else 64
    settings = {
        "map": header.get("map_name", ""),
        "tick_rate": tick_rate,
        "round_time_s": number(convars, "mp_roundtime", 1.92) * 60,
        "c4_timer_s": number(convars, "mp_c4timer", 40),
        "max_rounds": int(number(convars, "mp_maxrounds", 24)),
    }

    rounds = read(d, "rounds")
    snaps = read(d, "snapshots")
    econ = read(d, "round_economy")
    bomb = read(d, "bomb")
    kills = read(d, "kills")

    plants = (
        bomb.filter(pl.col("event") == "finish_plant")
        .group_by("part", "round_num")
        .agg(plant_tick=pl.col("tick").min(), plant_site=pl.col("bombsite").first())
    )
    first_death = (
        kills.filter(pl.col("in_play"))
        .sort("tick")
        .group_by("part", "round_num")
        .agg(first_death_side=pl.col("victim_side").first())
    )
    econ_cols = []
    for side, p in SIDE_PREFIX.items():
        econ_cols.append(
            econ.filter(pl.col("side") == side).select(
                "part",
                "round_num",
                pl.col("buy_type").alias(f"{p}_buy_type"),
                pl.col("equipment_value").alias(f"{p}_equipment_freeze_end"),
            )
        )

    out = (
        rounds.select(
            "part",
            "round_num",
            "freeze_end_tick",
            "end_tick",
            "winner_side",
            "reason_name",
            "is_overtime",
        )
        .join(side_teams(snaps), on=["part", "round_num"], how="left")
        .join(econ_cols[0], on=["part", "round_num"], how="left")
        .join(econ_cols[1], on=["part", "round_num"], how="left")
        .join(plants, on=["part", "round_num"], how="left")
        .join(first_death, on=["part", "round_num"], how="left")
        .sort("round_num")
        .with_columns(
            match_id=pl.lit(match_id),
            map=pl.lit(settings["map"]),
            winner_team=pl.when(pl.col("winner_side") == CT)
            .then(pl.col("ct_team"))
            .otherwise(pl.col("t_team")),
            ct_win=pl.col("winner_side") == CT,
            is_pistol_round=pl.col("round_num").is_in(
                [1, settings["max_rounds"] // 2 + 1]
            ),
            bomb_planted=pl.col("plant_tick").is_not_null(),
            round_duration_s=(pl.col("end_tick") - pl.col("freeze_end_tick"))
            / tick_rate,
        )
    )

    # Score before each round and the previous round's winner, by team.
    wins: dict[str, int] = {}
    ct_before, t_before, ct_won_prev = [], [], []
    prev_winner = None
    for r in out.iter_rows(named=True):
        ct_before.append(wins.get(r["ct_team"], 0))
        t_before.append(wins.get(r["t_team"], 0))
        ct_won_prev.append(None if prev_winner is None else prev_winner == r["ct_team"])
        prev_winner = r["winner_team"]
        wins[prev_winner] = wins.get(prev_winner, 0) + 1
    out = out.with_columns(
        ct_score_before=pl.Series(ct_before, dtype=pl.Int32),
        t_score_before=pl.Series(t_before, dtype=pl.Int32),
        ct_won_previous_round=pl.Series(ct_won_prev, dtype=pl.Boolean),
    )

    columns = [
        "match_id",
        "map",
        "part",
        "round_num",
        "is_overtime",
        "is_pistol_round",
        "ct_team",
        "t_team",
        "ct_score_before",
        "t_score_before",
        "ct_won_previous_round",
        "ct_buy_type",
        "t_buy_type",
        "ct_equipment_freeze_end",
        "t_equipment_freeze_end",
        "bomb_planted",
        "plant_site",
        "first_death_side",
        "freeze_end_tick",
        "plant_tick",
        "end_tick",
        "round_duration_s",
        "winner_side",
        "winner_team",
        "ct_win",
        "reason_name",
    ]
    return out.select(columns), settings


def side_aggregates(alive: pl.DataFrame, side: str) -> pl.DataFrame:
    p = SIDE_PREFIX[side]
    return (
        alive.filter(pl.col("side") == side)
        .group_by("part", "round_num", "tick")
        .agg(
            pl.len().alias(f"{p}_alive"),
            pl.col("health").sum().alias(f"{p}_hp"),
            pl.col("armor").sum().alias(f"{p}_armor"),
            pl.col("has_helmet").sum().alias(f"{p}_helmets"),
            pl.col("has_defuser").sum().alias(f"{p}_defusers"),
            pl.col("equipment_value").sum().alias(f"{p}_equipment"),
            pl.col("money").sum().alias(f"{p}_money"),
            pl.col("primary_weapon").is_in(RIFLES).sum().alias(f"{p}_rifles"),
            (pl.col("primary_weapon") == "awp").sum().alias(f"{p}_awps"),
            pl.col("primary_weapon").is_in(SMGS).sum().alias(f"{p}_smgs"),
            pl.col("smoke_grenades").sum().alias(f"{p}_smokes"),
            pl.col("flashbangs").sum().alias(f"{p}_flashes"),
            pl.col("he_grenades").sum().alias(f"{p}_he"),
            pl.col("fire_grenades").sum().alias(f"{p}_molotovs"),
            pl.col("has_bomb").any().alias(f"{p}_has_bomb"),
        )
    )


def build_states(d: Path, rounds: pl.DataFrame, settings: dict) -> pl.DataFrame:
    snaps = read(d, "snapshots")
    alive = snaps.filter(pl.col("health") > 0)
    keys = ["part", "round_num", "tick"]

    states = snaps.select(keys).unique()
    for side in (CT, T):
        states = states.join(side_aggregates(alive, side), on=keys, how="left")
    count_cols = [
        c for c in states.columns if c not in keys and not c.endswith("has_bomb")
    ]
    states = states.with_columns(
        [pl.col(c).fill_null(0).cast(pl.Int32) for c in count_cols]
        + [pl.col("t_has_bomb").fill_null(False)]
    ).drop("ct_has_bomb")

    tick_rate = settings["tick_rate"]
    states = (
        states.join(
            rounds.select(
                "match_id",
                "map",
                "part",
                "round_num",
                "freeze_end_tick",
                "plant_tick",
                "plant_site",
                "ct_team",
                "t_team",
                "ct_score_before",
                "t_score_before",
                "winner_side",
                "ct_win",
            ),
            on=["part", "round_num"],
            how="left",
        )
        .with_columns(
            seconds=(pl.col("tick") - pl.col("freeze_end_tick")) / tick_rate,
            bomb_planted=pl.col("plant_tick").is_not_null()
            & (pl.col("tick") >= pl.col("plant_tick")),
        )
        .with_columns(
            seconds_since_plant=pl.when(pl.col("bomb_planted")).then(
                (pl.col("tick") - pl.col("plant_tick")) / tick_rate
            ),
            plant_site=pl.when(pl.col("bomb_planted")).then(pl.col("plant_site")),
            bomb_carried=pl.col("t_has_bomb") & ~pl.col("bomb_planted"),
        )
        .with_columns(
            time_remaining_s=pl.when(pl.col("bomb_planted"))
            .then(settings["c4_timer_s"] - pl.col("seconds_since_plant"))
            .otherwise(settings["round_time_s"] - pl.col("seconds")),
        )
        .drop("t_has_bomb", "freeze_end_tick", "plant_tick")
    )

    front = [
        "match_id",
        "map",
        "part",
        "round_num",
        "tick",
        "seconds",
        "time_remaining_s",
        "bomb_planted",
        "seconds_since_plant",
        "plant_site",
        "bomb_carried",
        "ct_team",
        "t_team",
        "ct_score_before",
        "t_score_before",
    ]
    labels = ["winner_side", "ct_win"]
    middle = [c for c in states.columns if c not in front + labels]
    return states.select(front + middle + labels).sort("part", "round_num", "tick")


def main() -> int:
    args = parse_args()
    matches = sorted(p for p in args.input.iterdir() if p.is_dir())
    if not matches:
        print(f"No match folders in {args.input}", file=sys.stderr)
        return 1

    all_rounds, all_states = [], []
    for i, d in enumerate(matches, 1):
        rounds, settings = build_rounds(d.name, d)
        states = build_states(d, rounds, settings)
        all_rounds.append(rounds)
        all_states.append(states)
        print(
            f"[{i}/{len(matches)}] {d.name}: {rounds.height} rounds, "
            f"{states.height} states"
        )

    rounds = pl.concat(all_rounds, how="diagonal_relaxed")
    states = pl.concat(all_states, how="diagonal_relaxed")

    args.output.mkdir(parents=True, exist_ok=True)
    for name, df in (("rounds", rounds), ("round_states", states)):
        df.write_parquet(args.output / f"{name}.parquet")
        if not args.no_csv:
            df.write_csv(args.output / f"{name}.csv")

    teams = sorted(
        set(rounds["ct_team"].drop_nulls()) | set(rounds["t_team"].drop_nulls())
    )
    print(f"\nrounds: {rounds.height} rows, {rounds.width} columns")
    print(f"round_states: {states.height} rows, {states.width} columns")
    print(f"teams ({len(teams)}): {', '.join(teams)}")
    missing = rounds.filter(pl.col("ct_team").is_null() | pl.col("t_team").is_null())
    if missing.height:
        print(f"WARNING: {missing.height} rounds without a team name", file=sys.stderr)
    print(f"Written to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
