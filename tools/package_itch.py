"""Build upload-ready itch.io archives from the Godot release presets."""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build" / "itch"
WEB = OUTPUT / "web"
WINDOWS = OUTPUT / "windows"


def run(command: list[str], log_name: str) -> None:
    with (OUTPUT / log_name).open("w", encoding="utf-8") as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=False)
    if result.returncode != 0:
        lines = (OUTPUT / log_name).read_text(encoding="utf-8", errors="replace").splitlines()
        raise RuntimeError(f"{' '.join(command[:3])} failed:\n" + "\n".join(lines[-20:]))


def clean_stage(path: Path) -> None:
    # Only remove this script's ignored output, never an arbitrary caller path.
    if path.resolve().parent != OUTPUT.resolve() or path.name not in {"web", "windows"}:
        raise ValueError(f"Unexpected staging directory: {path}")
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def archive(stage: Path, output_name: str) -> Path:
    destination = OUTPUT / output_name
    files = sorted(path for path in stage.rglob("*") if path.is_file())
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zipped:
        for path in files:
            zipped.write(path, path.relative_to(stage).as_posix())
    with zipfile.ZipFile(destination) as zipped:
        bad = zipped.testzip()
        if bad is not None:
            raise RuntimeError(f"Corrupt ZIP member: {bad}")
    return destination


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    godot = shutil.which("godot")
    if godot is None:
        raise RuntimeError("Godot 4.7.2 must be available as 'godot' on PATH")
    godot_version = subprocess.check_output([godot, "--version"], cwd=ROOT, text=True).strip()
    if not godot_version.startswith("4.7.2.stable"):
        raise RuntimeError(f"Expected Godot 4.7.2, found {godot_version}")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    clean_stage(WEB)
    clean_stage(WINDOWS)

    git = ["git", "-c", f"safe.directory={ROOT.as_posix()}"]
    revision = subprocess.check_output(git + ["rev-parse", "--short=7", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = subprocess.run(git + ["diff", "--quiet", "HEAD", "--"], cwd=ROOT, check=False).returncode != 0
    build_date = datetime.now(timezone(timedelta(hours=9))).strftime("%Y-%m-%d")
    version_args = ["dirty"] if dirty else []
    run([godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
         "--script", "res://tools/inject_build_version.gd", "--", build_date, revision] + version_args,
        "version.log")
    run([godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
         "--export-release", "Web", str(WEB / "index.html")], "web-export.log")
    run([godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
         "--export-release", "Windows Desktop", str(WINDOWS / "Airscain.exe")],
        "windows-export.log")

    required_web = {"index.html", "index.js", "index.wasm", "index.pck",
                    "index.audio.worklet.js", "index.audio.position.worklet.js"}
    missing = required_web - {path.name for path in WEB.iterdir()}
    if missing:
        raise RuntimeError(f"Web export is incomplete: {sorted(missing)}")
    for name in ("Airscain.exe", "Airscain.pck"):
        if not (WINDOWS / name).is_file():
            raise RuntimeError(f"Windows export is incomplete: {name}")

    (WINDOWS / "README.txt").write_text(
        "AIRSCAIN — Windows x64\n"
        "Airscain.exe와 Airscain.pck를 같은 폴더에 둔 채 Airscain.exe를 실행하세요.\n"
        "Keep Airscain.exe and Airscain.pck together, then run Airscain.exe.\n"
        "Language can be changed in Settings. / 언어는 설정에서 변경할 수 있습니다.\n",
        encoding="utf-8",
    )
    web_files = [path for path in WEB.rglob("*") if path.is_file()]
    if len(web_files) > 1000 or any(path.stat().st_size > 200_000_000 for path in web_files):
        raise RuntimeError("Web export exceeds itch.io's HTML ZIP file limits")
    if any(len(path.relative_to(WEB).as_posix()) > 240 for path in web_files):
        raise RuntimeError("Web export exceeds itch.io's HTML ZIP filename limit")
    if sum(path.stat().st_size for path in web_files) > 500_000_000:
        raise RuntimeError("Web export exceeds itch.io's HTML ZIP extraction limit")

    archives = [archive(WEB, "Airscain-web-itch.zip"),
                archive(WINDOWS, "Airscain-windows-x64.zip")]
    (OUTPUT / "SHA256SUMS.txt").write_text(
        "".join(f"{sha256(path)}  {path.name}\n" for path in archives), encoding="ascii"
    )
    for path in archives:
        print(f"{path} ({path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
