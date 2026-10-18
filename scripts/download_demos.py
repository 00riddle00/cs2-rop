"""Download the manifest's project demos, verifying SHA-256 before replacement."""

import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download_demos() -> None:
    manifest = json.loads(
        (ROOT / "data" / "raw_checksums.json").read_text(encoding="utf-8")
    )
    if not isinstance(manifest, dict) or not manifest:
        raise ValueError("data/raw_checksums.json must contain demo records")
    for name, entry in manifest.items():
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*\.dem", name):
            raise ValueError(
                f"Invalid demo filename in data/raw_checksums.json: {name!r}"
            )
        if not isinstance(entry, dict):
            raise ValueError(
                f"Invalid demo record for {name} in data/raw_checksums.json"
            )
        file_id = entry.get("drive_id")
        if not isinstance(file_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", file_id):
            raise ValueError(
                f"Missing or invalid Drive ID for {name} in data/raw_checksums.json"
            )
        expected = entry.get("sha256")
        if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise ValueError(
                f"Missing or invalid SHA-256 for {name} in data/raw_checksums.json"
            )

    raw_dir = ROOT / "data" / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)
    for name, entry in manifest.items():
        destination = raw_dir / name
        file_id = entry["drive_id"]
        expected = entry["sha256"]
        if destination.is_file() and sha256(destination) == expected:
            print(f"{name}: already present, SHA-256 verified - skipping.", flush=True)
            continue
        if destination.exists():
            print(
                f"{name}: invalid existing file; downloading a replacement.", flush=True
            )
        else:
            print(f"{name}: downloading from Google Drive.", flush=True)

        try:
            import gdown
        except ImportError as exc:
            raise RuntimeError(
                "gdown is unavailable. Run uv sync, then retry."
            ) from exc

        # Keep the temporary download on the destination filesystem for os.replace.
        with tempfile.TemporaryDirectory(prefix=".download-", dir=raw_dir) as directory:
            partial = Path(directory) / name
            try:
                # Own the file handle so it closes even if gdown is interrupted.
                with partial.open("wb") as stream:
                    gdown.download(id=file_id, output=stream, use_cookies=False)
            except Exception as exc:
                raise RuntimeError(
                    f"{name}: download failed: {exc}\n"
                    "Check your connection and "
                    f"https://drive.google.com/file/d/{file_id}/view. "
                    "The file must allow public downloads; "
                    "Drive quotas may require retrying later."
                ) from exc
            actual = sha256(partial)
            if actual != expected:
                raise ValueError(
                    f"{name}: SHA-256 mismatch; download discarded.\n"
                    f"Expected: {expected}\nActual:   {actual}\n"
                    "Retry the download. If this persists, "
                    "check the shared source with the team."
                )
            os.replace(partial, destination)
        print(f"{name}: downloaded and SHA-256 verified.", flush=True)


def main() -> int:
    try:
        download_demos()
        return 0
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"download-demos: FAIL: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("download-demos: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
