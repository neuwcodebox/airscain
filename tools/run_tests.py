#!/usr/bin/env python3
"""Run all GUT scripts in isolated Godot processes, then the web audio tests."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed


ROOT = Path(__file__).resolve().parents[1]
TEST_PATTERN = re.compile(r"^func test_", re.MULTILINE)


def test_scripts() -> list[tuple[Path, int]]:
    scripts = []
    for path in sorted((ROOT / "tests").glob("**/test_*.gd")):
        count = len(TEST_PATTERN.findall(path.read_text(encoding="utf-8")))
        if count:
            # Full scenes cost more than the isolated rules in unit tests.
            weight = count * (5 if path.parent.name == "integration" else 1)
            scripts.append((path, weight))
    return scripts


def distribute(scripts: list[tuple[Path, int]], jobs: int) -> list[list[Path]]:
    shards: list[list[Path]] = [[] for _ in range(jobs)]
    weights = [0] * jobs
    for path, weight in sorted(scripts, key=lambda item: (-item[1], str(item[0]))):
        index = weights.index(min(weights))
        shards[index].append(path)
        weights[index] += weight
    return [shard for shard in shards if shard]


def run_shard(index: int, scripts: list[Path], godot: str, work: Path) -> tuple[int, int, str, float]:
    data = work / f"user-data-{index}"
    data.mkdir()
    log = work / f"shard-{index}.log"
    paths = ",".join(f"res://{path.relative_to(ROOT).as_posix()}" for path in scripts)
    env = dict(os.environ, XDG_DATA_HOME=str(data))
    command = [godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
               "-s", "addons/gut/gut_cmdln.gd", f"-gtest={paths}", "-gexit"]
    started = time.monotonic()
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=output,
                                stderr=subprocess.STDOUT, check=False)
    elapsed = time.monotonic() - started
    output_text = log.read_text(encoding="utf-8", errors="replace")
    summary = re.search(r"(?m)^Scripts\s+(\d+)\s*$", output_text)
    ran = re.search(r"(?m)^Tests\s+(\d+)\s*$", output_text)
    expected = sum(len(TEST_PATTERN.findall(path.read_text(encoding="utf-8"))) for path in scripts)
    # A missing class import can make GUT exit successfully without running tests.
    complete = (summary is not None and int(summary.group(1)) == len(scripts)
                and ran is not None and int(ran.group(1)) == expected
                and "Risky/Pending" not in output_text)
    return index, result.returncode if complete else 1, str(log), elapsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=3, help="concurrent Godot processes (default: 3)")
    parser.add_argument("--godot", default="godot", help="Godot executable")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    scripts = test_scripts()
    if not scripts:
        parser.error("no GUT tests found")
    shards = distribute(scripts, min(args.jobs, len(scripts)))
    print(f"Running {len(scripts)} GUT scripts in {len(shards)} isolated processes", flush=True)
    failed = False
    with tempfile.TemporaryDirectory(prefix="airscain-tests-") as directory:
        work = Path(directory)
        with ThreadPoolExecutor(max_workers=len(shards)) as executor:
            tasks = [executor.submit(run_shard, i, shard, args.godot, work)
                     for i, shard in enumerate(shards, 1)]
            for task in as_completed(tasks):
                index, code, log, elapsed = task.result()
                print(f"Shard {index}: {'PASS' if code == 0 else 'FAIL'} "
                      f"({len(shards[index - 1])} scripts, {elapsed:.1f}s)", flush=True)
                if code != 0:
                    failed = True
                    print(Path(log).read_text(encoding="utf-8", errors="replace")[-12000:], file=sys.stderr)
        if failed:
            print("GUT failed; rerun the named scripts directly for full output.", file=sys.stderr)
            return 1
    web = subprocess.run(["node", str(ROOT / "tests/unit/test_web_sample_playback.js")], cwd=ROOT, check=False)
    return web.returncode


if __name__ == "__main__":
    sys.exit(main())
