"""Export one processed match to CSV files for a quick look.

Writes <output>/<match_id>/<table>.csv for every Parquet table, capped
at --max-rows rows each (0 exports all rows), and
<output>/<match_id>/overview.csv listing each table with its full row
count and columns.

--output defaults to data/csv_export.

Usage (from the repo root):
    uv run python scripts/export_csv_sample.py --match mouz-vs-spirit-m1-dust2 \
        --output data/awpy_parser_data --max-rows 0
"""

import argparse
from pathlib import Path

import polars as pl

ap = argparse.ArgumentParser(description=__doc__,
                             formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--match", required=True, help="Match folder name in --processed")
ap.add_argument("--processed", type=Path, default=Path("data/processed"))
ap.add_argument("--output", type=Path, default=Path("data/csv_export"),
                help="Folder for the CSV export (default data/csv_export)")
ap.add_argument("--max-rows", type=int, default=5000,
                help="Rows per CSV; 0 exports all rows (default 5000)")
args = ap.parse_args()

src = args.processed / args.match
dst = args.output / args.match
dst.mkdir(parents=True, exist_ok=True)

overview = []
for f in sorted(src.glob("*.parquet")):
    df = pl.read_parquet(f)
    out = df if args.max_rows == 0 else df.head(args.max_rows)
    out.write_csv(dst / f"{f.stem}.csv")
    overview.append({"table": f.stem, "rows": df.height, "columns": df.width,
                     "column_names": ", ".join(df.columns)})

pl.DataFrame(overview).write_csv(dst / "overview.csv")
print(pl.DataFrame(overview).select("table", "rows", "columns"))
print(f"Written to {dst}")
