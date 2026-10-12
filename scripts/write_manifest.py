#!/usr/bin/env python3
"""Records what a benchmark run measured, and on what, as JSON.

The result table only names builds by label; the manifest ties every label to
the commit it was built from and keeps the settings, file hashes, harness
revisions and machine a run depends on, so the run can be read and repeated
without its command line.

usage: write_manifest.py -o manifest.json --root <repo>
           --build <method> <tool> <rev> <commit> [--build ...]
           --set <key> <value> [--set ...] --file <path> [--file ...]
"""

import argparse
import datetime
import hashlib
import json
import os
import platform
import subprocess


def run(*cmd, cwd=None):
    try:
        out = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    return out.stdout.strip()


def repo_state(path):
    commit = run("git", "-C", path, "rev-parse", "HEAD")
    if commit is None:
        return None
    dirty = run("git", "-C", path, "status", "--porcelain", "--untracked-files=no")
    return {"commit": commit, "dirty": bool(dirty)}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fd:
        for chunk in iter(lambda: fd.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def cpu_model():
    try:
        with open("/proc/cpuinfo") as fd:
            for line in fd:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or None


def governors(cpus):
    result = {}
    for cpu in cpus:
        try:
            with open(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_governor") as fd:
                result[cpu] = fd.read().strip()
        except OSError:
            result[cpu] = None
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--build", nargs=4, action="append", default=[],
                        metavar=("METHOD", "TOOL", "REV", "COMMIT"))
    parser.add_argument("--set", nargs=2, action="append", default=[], metavar=("KEY", "VALUE"))
    parser.add_argument("--file", action="append", default=[])
    args = parser.parse_args()

    settings = dict(args.set)
    cpus = settings.get("cpus", "").split()
    cxx = os.environ.get("CXX", "c++")
    manifest = {
        "date": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "settings": settings,
        "builds": [
            {"method": method, "tool": tool, "rev": rev, "commit": commit}
            for method, tool, rev, commit in args.build
        ],
        "files": {path: sha256(os.path.join(args.root, path)) for path in args.file},
        "repositories": {
            name: repo_state(os.path.join(args.root, name))
            for name in (".", "harnesses/pycobench", "harnesses/automata-program-parser",
                         "benchmarks/nfa-bench")
        },
        "machine": {
            "host": platform.node(),
            "system": " ".join(platform.uname()[i] for i in (0, 2, 4)),
            "cpu": cpu_model(),
            "cpu_count": os.cpu_count(),
            "governors": governors(cpus),
            "compiler": (run(cxx, "--version") or "").partition("\n")[0] or None,
            "python": platform.python_version(),
        },
    }
    with open(args.output, "w") as fd:
        json.dump(manifest, fd, indent=2)
        fd.write("\n")


if __name__ == "__main__":
    main()
