#!/usr/bin/env python3
"""Runs benchmark experiments: programs on inputs, measured on builds of tools.

An experiment runs one or more programs (an .emp program, interpreted by every
build, or a C++ program cc-programs/<name>.cc, compiled against every build),
optionally in several variants (extra arguments), on input lists, for one or
more builds ('<tool>:<rev>'). Every (build, program, variant) is one pycobench
method, so all of them are measured on exactly the same inputs into one table,
and the run ends with the tables and plots comparing them against the first.

Experiments are given either on the command line (--program, --input) or in
suite files (suites/*.toml), which define experiments, defaults and build sets,
and include other suites. See README.md, "Suites".

Examples:
  # one program, two revisions of mata
  scripts/bench.py --program emp-programs/determinize.emp \\
      --input inputs/bench-regexps_union.input v1.32.32 devel
  # a pull request against its base, on a suite, with three repetitions
  scripts/bench.py suites/tacas-24.toml --repeat 3 pr/885
  # two variants of a C++ program on one revision
  scripts/bench.py --program cc-programs/minimize.cc --input inputs/bench-regexps_union.input \\
      --variant brzozowski=--algorithm=brzozowski --variant hopcroft=--algorithm=hopcroft devel
"""

import argparse
import datetime
import glob
import itertools
import json
import os
import re
import shlex
import subprocess
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Settings, their types and their built-in defaults. Precedence, lowest first:
# these, the [defaults] of the suite defining the experiment, the [defaults] of
# the suites including that one (outermost last), the experiment's own keys,
# the command line.
SETTINGS = {
    "timeout": (int, 60),
    "jobs": (int, 6),
    "repeat": (int, 1),
    "memout": (int, None),
    "pin": (bool, True),
    "build_mode": (str, "Release"),
}
KIND_NAMES = {int: "an integer", bool: "true or false", str: "a string"}
EXPERIMENT_KEYS = {"description", "extends", "program", "programs", "variants", "inputs", "builds"}
NAME = re.compile(r"[A-Za-z0-9_.-]+")
WILDCARD = re.compile(r"[*?\[]")


def die(message):
    sys.exit(f"error: {message}")


def label_of(text):
    """Folds what a revision may contain ('/', '^', '~', ':') away, as labels end up in column,
    file and legend names."""
    return re.sub(r"[^A-Za-z0-9._-]+", "-", text).rstrip("-")


# === Suites ===


@dataclass
class Experiment:
    name: str
    source: str
    table: dict
    # [defaults] tables that apply, innermost (the defining suite) first.
    defaults: list = field(default_factory=list)


@dataclass
class Suites:
    experiments: dict = field(default_factory=dict)
    build_sets: dict = field(default_factory=dict)
    files: list = field(default_factory=list)


def check_settings(table, where, extra=()):
    for key, value in table.items():
        if key in extra:
            continue
        if key not in SETTINGS:
            die(f"{where}: unknown key '{key}'")
        kind = SETTINGS[key][0]
        if not isinstance(value, kind) or (kind is int and isinstance(value, bool)):
            die(f"{where}: '{key}' must be {KIND_NAMES[kind]}, not {value!r}")


def load_suite(path, suites, outer=(), stack=()):
    """Loads the suite at @path and what it includes into @suites."""
    path = path.resolve()
    if path in stack:
        die(f"{path}: included from itself ({' -> '.join(map(str, stack))})")
    try:
        with open(path, "rb") as fd:
            doc = tomllib.load(fd)
    except OSError as error:
        die(f"cannot read suite {path}: {error.strerror}")
    except tomllib.TOMLDecodeError as error:
        die(f"{path}: {error}")
    where = os.path.relpath(path, ROOT) if path.is_relative_to(ROOT) else str(path)
    for key in doc:
        if key not in ("include", "defaults", "builds", "experiment"):
            die(f"{where}: unknown top-level key '{key}'")
    defaults = doc.get("defaults", {})
    check_settings(defaults, f"{where} [defaults]", extra=("builds",))
    chain = [defaults, *outer]
    if path not in suites.files:
        suites.files.append(path)

    for item in doc.get("include", []):
        if isinstance(item, str):
            item = {"path": item}
        if not isinstance(item, dict) or "path" not in item or set(item) - {"path", "only"}:
            die(f"{where}: an include is a path or {{ path = ..., only = [...] }}, not {item!r}")
        included = Suites()
        load_suite(path.parent / item["path"], included, chain, (*stack, path))
        only = item.get("only")
        for name in only or []:
            if name not in included.experiments:
                die(f"{where}: {item['path']} has no experiment '{name}'")
        for name, experiment in included.experiments.items():
            if only is None or name in only:
                add_experiment(suites, experiment, where)
        suites.build_sets.update(included.build_sets)
        suites.files += [f for f in included.files if f not in suites.files]

    for name, specs in doc.get("builds", {}).items():
        if not isinstance(specs, list) or not all(isinstance(s, str) for s in specs):
            die(f"{where}: build set '{name}' must be a list of build specs")
        suites.build_sets[name] = specs
    for name, table in doc.get("experiment", {}).items():
        if not NAME.fullmatch(name):
            die(f"{where}: experiment name '{name}' is not [A-Za-z0-9_.-]+")
        check_settings(table, f"{where} [experiment.{name}]", extra=EXPERIMENT_KEYS)
        add_experiment(suites, Experiment(name, where, table, chain), where)


def add_experiment(suites, experiment, where):
    known = suites.experiments.get(experiment.name)
    if known is not None and (known.source, known.table) != (experiment.source, experiment.table):
        die(f"{where}: experiment '{experiment.name}' is defined both in {known.source} and {experiment.source}")
    suites.experiments.setdefault(experiment.name, experiment)


def resolve_extends(suites, name, seen=()):
    """The table of experiment @name with what it extends filled in."""
    experiment = suites.experiments[name]
    parent = experiment.table.get("extends")
    if parent is None:
        return dict(experiment.table)
    if parent not in suites.experiments:
        die(f"{experiment.source}: experiment '{name}' extends unknown experiment '{parent}'")
    if parent in seen:
        die(f"{experiment.source}: experiment '{name}' is part of an 'extends' cycle")
    table = resolve_extends(suites, parent, (*seen, name))
    # 'program' and 'programs' are one setting spelt two ways.
    for key, other in (("program", "programs"), ("programs", "program")):
        if key in experiment.table:
            table.pop(other, None)
    table.update(experiment.table)
    del table["extends"]
    return table


# === Plans: what an experiment runs ===


@dataclass
class Plan:
    name: str
    source: str
    description: str
    programs: list  # paths relative to the root; [] when the inputs name the program
    variants: dict  # name -> [args]; {"": []} for none
    inputs: list  # (name, path or generator table)
    specs: list
    settings: dict


def as_list(value):
    return value if isinstance(value, list) else [value]


def make_plan(name, source, table, defaults, cli_settings, cli_specs, build_sets):
    where = f"{source} [experiment.{name}]"
    if "program" in table and "programs" in table:
        die(f"{where}: give 'program' or 'programs', not both")
    programs = as_list(table.get("program", table.get("programs", [])))
    for program in programs:
        if not isinstance(program, str):
            die(f"{where}: a program is a path, not {program!r}")
        if not (ROOT / program).is_file():
            die(f"{where}: no such program: {program}")
        if Path(program).suffix not in (".emp", ".cc"):
            die(f"{where}: {program} is neither an .emp nor a .cc program")
    stems = [Path(p).stem for p in programs]
    if len(set(stems)) < len(stems):
        die(f"{where}: two programs share a name: {', '.join(programs)}")

    variants = {}
    for variant, args in table.get("variants", {}).items():
        if not NAME.fullmatch(variant):
            die(f"{where}: variant name '{variant}' is not [A-Za-z0-9_.-]+")
        args = shlex.split(args) if isinstance(args, str) else args
        if not isinstance(args, list) or not all(isinstance(a, str) and a.split() == [a] for a in args):
            die(f"{where}: variant '{variant}' must be arguments without whitespace, not {args!r}")
        variants[variant] = args

    inputs = []
    entries = as_list(table.get("inputs", []))
    if not entries:
        die(f"{where}: no inputs")
    generated = [e for e in entries if not isinstance(e, str) or WILDCARD.search(e)]
    for entry in entries:
        if isinstance(entry, str) and not WILDCARD.search(entry):
            if not (ROOT / entry).is_file():
                die(f"{where}: no such input file: {entry}")
            inputs.append((Path(entry).stem, entry))
            continue
        generator = {"glob": entry} if isinstance(entry, str) else entry
        if (
            not isinstance(generator, dict)
            or "glob" not in generator
            or set(generator) - {"glob", "columns", "combine", "name"}
        ):
            die(
                f"{where}: an input is an .input file, a glob or {{ glob = ..., columns = [...], "
                f"combine = <k>, name = ... }}, not {entry!r}"
            )
        default = name if len(generated) == 1 else f"{name}-{len(inputs) + 1}"
        if not NAME.fullmatch(input_name := generator.get("name", default)):
            die(f"{where}: input name '{input_name}' is not [A-Za-z0-9_.-]+")
        inputs.append((input_name, generator))
    names = [n for n, _ in inputs]
    for duplicate in {n for n in names if names.count(n) > 1}:
        die(f"{where}: two input lists are both named '{duplicate}'; name them apart")

    settings = {key: default for key, (_, default) in SETTINGS.items()}
    merged_builds = None
    for layer in defaults:
        settings.update({k: v for k, v in layer.items() if k != "builds"})
        merged_builds = layer.get("builds", merged_builds)
    settings.update({k: v for k, v in table.items() if k in SETTINGS})
    settings.update(cli_settings)
    specs = cli_specs or table.get("builds") or merged_builds or []
    if not isinstance(specs, list) or not all(isinstance(s, str) for s in specs):
        die(f"{where}: 'builds' must be a list of build specs")
    return Plan(
        name,
        source,
        table.get("description", ""),
        programs,
        variants or {"": []},
        inputs,
        expand_sets(specs, build_sets, where),
        settings,
    )


def expand_sets(specs, build_sets, where, seen=()):
    expanded = []
    for spec in specs:
        if not spec.startswith("@"):
            expanded.append(spec)
            continue
        if spec[1:] not in build_sets:
            die(f"{where}: unknown build set '{spec}' (known: {', '.join(build_sets) or 'none'})")
        if spec in seen:
            die(f"{where}: build set '{spec}' includes itself")
        expanded += expand_sets(build_sets[spec[1:]], build_sets, where, (*seen, spec))
    return expanded


# === Inputs ===


def generate_input(generator, where):
    """The lines of a generated input list: one per file matched by 'glob', or per k-combination
    of them ('combine'), or per match with 'columns' templates filled in."""
    pattern = generator["glob"]
    matches = sorted(os.path.relpath(p, ROOT) for p in glob.glob(str(ROOT / pattern), recursive=True))
    if not matches:
        die(f"{where}: glob '{pattern}' matches no file")
    if "combine" in generator:
        if "columns" in generator:
            die(f"{where}: give 'columns' or 'combine', not both")
        k = generator["combine"]
        if not isinstance(k, int) or k < 2:
            die(f"{where}: 'combine' must be an integer >= 2")
        return [[f"./{p}" for p in combination] for combination in itertools.combinations(matches, k)]
    columns = generator.get("columns", ["{path}"])
    # The stem is a match without the literal text that ends the pattern, so
    # that 'a/*-lhs.mata' gives the stem 'a/x' of 'a/x-lhs.mata'.
    suffix = re.split(r"[*?\]]", pattern)[-1]
    lines, skipped = [], 0
    for match in matches:
        stem = match[: len(match) - len(suffix)] if suffix else match
        line = [c.format(path=match, stem=stem) for c in columns]
        # A column that is still a glob is expanded by pycobench at run time,
        # which is how one line feeds a variable number of automata.
        if all(glob.glob(str(ROOT / c)) if WILDCARD.search(c) else (ROOT / c).is_file() for c in line):
            lines.append([f"./{c}" for c in line])
        else:
            skipped += 1
    if skipped:
        print(
            f"[!] {where}: skipped {skipped} of {len(matches)} matches of '{pattern}' whose columns do not all exist",
            file=sys.stderr,
        )
    if not lines:
        die(f"{where}: no match of '{pattern}' has all its columns")
    return lines


def materialize_inputs(plan, run_dir):
    """Writes the generated input lists into the run and returns the paths of all of them,
    relative to the root."""
    paths = []
    for name, source in plan.inputs:
        if isinstance(source, str):
            paths.append(source)
            continue
        lines = generate_input(source, f"{plan.source} [experiment.{plan.name}] inputs '{name}'")
        path = run_dir / "inputs" / f"{name}.input"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(";".join(line) + "\n" for line in lines))
        paths.append(os.path.relpath(path, ROOT))
    return paths


def input_arity(paths, where):
    """The number of ';'-separated columns, which every line of every input must share."""
    arity = None
    for path in paths:
        for number, line in enumerate((ROOT / path).read_text().splitlines(), 1):
            if not line.strip():
                continue
            columns = line.count(";") + 1
            if arity is None:
                arity = columns
            elif columns != arity:
                die(f"{where}: {path}:{number} has {columns} columns, the first line {arity}")
    if arity is None:
        die(f"{where}: the inputs are empty")
    return arity


def program_in_input(paths):
    """Whether the inputs name the program in their first column."""
    first = (ROOT / paths[0]).read_text().split("\n", 1)[0].split(";")[0]
    return first.endswith(".emp")


# === Builds ===


@dataclass(frozen=True)
class Tool:
    name: str
    subject: str
    runs: tuple

    @property
    def is_git(self):
        return not self.subject.startswith(("pypi:", "tarball:"))


@dataclass(frozen=True)
class Build:
    tool: Tool
    rev: str
    label: str
    commit: str

    @property
    def method(self):
        return f"{self.tool.name}-{self.label}"

    @property
    def subject_name(self):
        subject = self.tool.subject
        if subject.startswith("pypi:"):
            return subject.removeprefix("pypi:")
        return self.tool.name if subject.startswith("tarball:") else Path(subject).name


def known_tools():
    out = run_output([str(ROOT / "scripts/build_version.sh"), "--list-tools"])
    tools = {}
    for line in out.splitlines():
        name, subject, *runs = line.split()
        tools[name] = Tool(name, subject, tuple(runs))
    return tools


def run_output(cmd, **kwargs):
    try:
        return subprocess.run(cmd, check=True, capture_output=True, text=True, **kwargs).stdout
    except subprocess.CalledProcessError as error:
        die(f"{' '.join(cmd)} failed:\n{error.stderr.strip()}")


class Resolver:
    """Turns build specs into builds, resolving revisions to commits once per run."""

    def __init__(self, dry=False):
        self.dry = dry
        self.tools = known_tools()
        self.prs = {}

    def resolve(self, specs, where):
        builds = []
        for spec in specs:
            tool_name, _, revs = spec.partition(":") if ":" in spec else ("", "", spec)
            tool = self.tools.get(tool_name or "mata")
            if tool is None:
                die(f"{where}: unknown tool '{tool_name}' in '{spec}' (known: {', '.join(self.tools)})")
            if not revs:
                die(f"{where}: spec '{spec}' lists no revision")
            for entry in revs.split(","):
                rev, _, label = entry.partition("=")
                if not rev:
                    die(f"{where}: spec '{spec}' lists an empty revision")
                if m := re.fullmatch(r"pr/(\d+)", rev):
                    # The one revision that stands for two: what the pull request
                    # changes and what it is measured against.
                    label = label or f"pr{m[1]}"
                    base, head = self.pr_commits(tool, m[1])
                    builds += [self.build(tool, base, f"{label}-base"), self.build(tool, head, f"{label}-head")]
                else:
                    builds.append(self.build(tool, rev, label or rev))
        methods = [b.method for b in builds]
        for method in methods:
            if methods.count(method) > 1:
                die(f"{where}: two builds are both labelled '{method}'; give one '<rev>=<label>'")
        return builds

    def build(self, tool, rev, label):
        if self.dry or not tool.is_git:
            return Build(tool, rev, label_of(label), rev)
        subject = ROOT / tool.subject
        result = subprocess.run(
            ["git", "-C", str(subject), "rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            die(
                f"{tool.name}: revision '{rev}' not found in {tool.subject} "
                f"(try 'git -C {tool.subject} fetch --all --tags')"
            )
        return Build(tool, rev, label_of(label), result.stdout.strip())

    def pr_commits(self, tool, number):
        """The base and the head of pull request @number of the tool's subject. Both are fetched,
        as the head lives in a 'pull/<N>/head' ref a plain clone lacks and the base may be newer
        than the last fetch."""
        if self.dry:
            return f"pr/{number}^base", f"pr/{number}"
        key = (tool.subject, number)
        if key in self.prs:
            return self.prs[key]
        if not tool.is_git:
            die(f"{tool.name}: 'pr/{number}' needs a git subject, not {tool.subject}")
        subject = str(ROOT / tool.subject)
        remotes = run_output(["git", "-C", subject, "remote"]).split()
        if not remotes:
            die(f"{tool.subject} has no remote to resolve 'pr/{number}' against")
        remote = "origin" if "origin" in remotes else remotes[0]
        url = run_output(["git", "-C", subject, "remote", "get-url", remote]).strip()
        slug = re.sub(r"\.git$", "", re.sub(r"^(git@[^:]+:|https?://[^/]+/)", "", url))
        base, head = run_output(
            ["gh", "api", f"repos/{slug}/pulls/{number}", "--jq", '"\\(.base.sha) \\(.head.sha)"']
        ).split()
        run_output(
            [
                "git",
                "-C",
                subject,
                "fetch",
                "--quiet",
                remote,
                f"+refs/pull/{number}/head:refs/remotes/{remote}/pr/{number}",
            ]
        )
        subprocess.run(["git", "-C", subject, "fetch", "--quiet", remote, base], capture_output=True)
        self.prs[key] = (base, head)
        return base, head


class Builder:
    """Builds every (build, build mode) and C++ program once per run."""

    def __init__(self, force):
        self.force = force
        self.done = set()

    def build(self, build, build_mode, program=None):
        key = (build, build_mode, program)
        if key in self.done:
            return
        cmd = [str(ROOT / "scripts/build_version.sh"), "--build-mode", build_mode]
        if self.force and (build, build_mode, None) not in self.done:
            cmd.append("--force")
        if program:
            cmd += ["--program", program]
        cmd += [build.tool.name, build.rev, build.label]
        if subprocess.run(cmd, cwd=ROOT).returncode != 0:
            die(f"building {build.method} failed")
        self.done |= {key, (build, build_mode, None)}


# === Running ===


@dataclass
class Method:
    name: str
    build: Build
    program: str  # '' when the inputs name it
    variant: str
    args: list

    def command(self, arity):
        params = [f"${i}" for i in range(1, arity + 1)]
        if self.program.endswith(".cc"):
            binary = (
                f"./build/versions/{self.build.subject_name}/{self.build.label}/"
                f"{self.build.tool.name}/programs/{Path(self.program).stem}"
            )
            return " ".join([binary, *self.args, *params])
        if self.program:
            return " ".join([f"./bin/{self.build.method}", f"./{self.program}", *self.args, *params])
        # The inputs name the program in their first column.
        return " ".join([f"./bin/{self.build.method}", params[0], *self.args, *params[1:]])


def methods_of(plan, builds, in_input):
    programs = plan.programs or [""]
    methods = []
    for build, program, (variant, args) in itertools.product(builds, programs, plan.variants.items()):
        kind = "cc" if program.endswith(".cc") else "emp"
        if kind not in build.tool.runs:
            die(
                f"{plan.source} [experiment.{plan.name}]: tool '{build.tool.name}' does not run "
                f"{kind} programs (runs: {' '.join(build.tool.runs)})"
            )
        name = build.method
        if len(programs) > 1:
            name += f".{Path(program).stem}"
        if variant:
            name += f".{variant}"
        methods.append(Method(name, build, program, variant, args))
    if in_input and plan.programs:
        die(f"{plan.source} [experiment.{plan.name}]: the inputs name their program; drop 'program'")
    if not in_input and not plan.programs:
        die(f"{plan.source} [experiment.{plan.name}]: no program, and the inputs do not name one")
    return methods


def pinned_cpus(n):
    """@n CPUs, one per physical core, skipping the core of CPU 0 where the kernel and interrupts
    tend to run, so that no two workers share a core's caches and execution units."""
    paths = glob.glob("/sys/devices/system/cpu/cpu[0-9]*/topology/thread_siblings_list")
    if not paths:
        die("pinning needs Linux CPU topology in /sys; pass --no-pin")
    cores = sorted({int(re.split(r"[,-]", Path(p).read_text())[0]) for p in paths} - {0})
    if len(cores) < n:
        die(f"--jobs {n} exceeds the {len(cores)} physical cores available for pinning; lower --jobs or pass --no-pin")
    return cores[:n]


def run_plan(plan, run_dir, resolver, builder, args, suite_files):
    where = f"{plan.source} [experiment.{plan.name}]"
    if not plan.specs:
        die(f"{where}: no builds; give them on the command line or as 'builds'")
    settings = plan.settings
    builds = resolver.resolve(plan.specs, where)

    run_dir.mkdir(parents=True, exist_ok=True)
    inputs = materialize_inputs(plan, run_dir)
    arity = input_arity(inputs, where)
    in_input = program_in_input(inputs)
    methods = methods_of(plan, builds, in_input)

    for method in methods:
        builder.build(method.build, settings["build_mode"], method.program if method.program.endswith(".cc") else None)

    config = run_dir / f"{plan.name}.yaml"
    with open(config, "w") as fd:
        fd.write("# Generated by scripts/bench.py -- regenerate, do not edit.\n")
        for method in methods:
            fd.write(f"\n{json.dumps(method.name)}:\n  cmd: {json.dumps(method.command(arity))}\n")
    for program in plan.programs:
        (run_dir / Path(program).name).write_bytes((ROOT / program).read_bytes())

    cpus = pinned_cpus(settings["jobs"]) if settings["pin"] else []
    manifest = [
        sys.executable,
        str(ROOT / "scripts/write_manifest.py"),
        "-o",
        str(run_dir / "manifest.json"),
        "--root",
        str(ROOT),
        "--file",
        os.path.relpath(config, ROOT),
    ]
    for method in methods:
        manifest += ["--build", method.name, method.build.tool.name, method.build.rev, method.build.commit]
    for path in [*plan.programs, *inputs, *(os.path.relpath(f, ROOT) for f in suite_files)]:
        manifest += ["--file", path]
    for key, value in {
        "experiment": plan.name,
        "suites": " ".join(os.path.relpath(f, ROOT) for f in suite_files),
        "programs": " ".join(plan.programs) or "<first column of the input>",
        "variants": json.dumps({v: a for v, a in plan.variants.items() if v}),
        "inputs": " ".join(inputs),
        **{k: "none" if v is None else str(v) for k, v in settings.items()},
        "cpus": " ".join(map(str, cpus)) or "unpinned",
        "test_run": str(args.test_run).lower(),
        "command": shlex.join(sys.argv),
    }.items():
        manifest += ["--set", key, value]
    subprocess.run(manifest, check=True, cwd=ROOT, env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"})

    print(f"[!] {plan.name}: {len(methods)} methods: {' '.join(m.name for m in methods)}")
    print(f"[!] Results: {os.path.relpath(run_dir, ROOT)} (manifest.json records the builds and settings)")
    measure = [
        "bash",
        str(ROOT / "scripts/run_pyco.sh"),
        "--config",
        os.path.relpath(config, ROOT),
        "--timeout",
        str(settings["timeout"]),
        "--jobs",
        str(settings["jobs"]),
        "--repeat",
        str(settings["repeat"]),
        "-s",
        os.path.relpath(run_dir, ROOT / "results/data"),
    ]
    if args.test_run:
        measure.insert(2, "--test-run")
    if settings["memout"] is not None:
        measure += ["--memout", str(settings["memout"])]
    if cpus:
        measure += ["--cpu-affinity", " ".join(map(str, cpus))]
    if subprocess.run([*measure, *inputs], cwd=ROOT).returncode != 0:
        die(f"{plan.name}: measuring failed")
    if (
        args.report
        and subprocess.run(
            [
                "bash",
                str(ROOT / "scripts/report.sh"),
                "--timeout",
                str(settings["timeout"]),
                "--baseline",
                methods[0].name,
                "--title",
                plan.name,
                os.path.relpath(run_dir, ROOT),
            ],
            cwd=ROOT,
        ).returncode
        != 0
    ):
        die(f"{plan.name}: reporting failed")


def describe(plan, resolver):
    """Prints what the experiment would run, without building or measuring anything."""
    where = f"{plan.source} [experiment.{plan.name}]"
    print(f"{plan.name}  ({plan.source})")
    if plan.description:
        print(f"  {plan.description}")
    first = None
    for name, source in plan.inputs:
        if isinstance(source, str):
            lines = [line.split(";") for line in (ROOT / source).read_text().splitlines() if line.strip()]
            print(f"  inputs:   {source} ({len(lines)} lines)")
        else:
            lines = generate_input(source, f"{where} inputs '{name}'")
            print(f"  inputs:   {name}: {len(lines)} lines from {json.dumps(source)}")
        first = first or lines[0]
    print(f"  settings: {' '.join(f'{k}={'none' if v is None else v}' for k, v in plan.settings.items())}")
    if not plan.specs:
        print("  methods:  <no builds: give them on the command line>")
        return
    builds = resolver.resolve(plan.specs, where)
    for method in methods_of(plan, builds, first[0].endswith(".emp")):
        print(
            f"  method:   {method.name} = {method.build.tool.name}:{method.build.rev} "
            f"{method.program or '<input>'} {' '.join(method.args)}".rstrip()
        )


# === Command line ===


def parse_args():
    parser = argparse.ArgumentParser(
        prog="scripts/bench.py",
        allow_abbrev=False,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=__doc__.split("\n\n", 1)[0],
        epilog=__doc__.split("\n\n", 1)[1],
    )
    parser.add_argument(
        "targets",
        nargs="*",
        metavar="SUITE.toml | BUILD",
        help="suite files, and builds '[<tool>:]<rev>[=<label>][,...]', 'pr/<N>' or "
        "'@<build set>'; builds given here replace those of every experiment",
    )
    parser.add_argument(
        "-p",
        "--program",
        action="append",
        default=[],
        help="ad hoc experiment: program to run (.emp or cc-programs/*.cc); repeatable",
    )
    parser.add_argument(
        "-i",
        "--input",
        action="append",
        default=[],
        help="ad hoc experiment: .input file or glob of .mata files; repeatable",
    )
    parser.add_argument(
        "-V",
        "--variant",
        action="append",
        default=[],
        metavar="NAME=ARGS",
        help="ad hoc experiment: run the programs also with these arguments; repeatable",
    )
    parser.add_argument("-n", "--name", help="ad hoc experiment: its name [default: the program's]")
    parser.add_argument("--only", help="run only these experiments of the suites (comma-separated)")
    parser.add_argument("--list", action="store_true", help="print the experiments as resolved and exit")
    parser.add_argument("-l", "--list-tools", action="store_true", help="list the known tools and exit")
    parser.add_argument("-t", "--timeout", type=int, help="timeout per benchmark in seconds [60]")
    parser.add_argument("-j", "--jobs", type=int, help="parallel jobs [6]")
    parser.add_argument("-r", "--repeat", type=int, help="measure every benchmark N times, keep the minimum [1]")
    parser.add_argument("-M", "--memout", type=int, help="memory limit per benchmark in GB [none]")
    parser.add_argument(
        "--pin",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="pin worker i to its own physical core, never CPU 0 [on]",
    )
    parser.add_argument("-b", "--build-mode", help="Release, RelWithDebInfo or Debug [Release]")
    parser.add_argument("-o", "--output-dir", help="store the run in results/data/<dir> [<name>-<timestamp>]")
    parser.add_argument("-f", "--force", action="store_true", help="rebuild the binaries even if they exist")
    parser.add_argument("-d", "--test-run", action="store_true", help="only run the first benchmark of each input")
    parser.add_argument("-R", "--no-report", dest="report", action="store_false", help="skip the plots and tables")
    # Intermixed: builds and suites may come before, between and after options.
    return parser.parse_intermixed_args()


def adhoc_table(args):
    table = {"inputs": args.input}
    if args.program:
        table["programs"] = args.program
    variants = {}
    for variant in args.variant:
        name, sep, value = variant.partition("=")
        if not sep:
            die(f"--variant '{variant}' is not NAME=ARGS")
        variants[name] = value
    if variants:
        table["variants"] = variants
    return table


def main():
    args = parse_args()
    if args.list_tools:
        os.execv(ROOT / "scripts/build_version.sh", [str(ROOT / "scripts/build_version.sh"), "--list-tools"])
    os.chdir(ROOT)

    suite_paths = [Path(t) for t in args.targets if t.endswith(".toml")]
    specs = [t for t in args.targets if not t.endswith(".toml")]
    cli_settings = {
        k: v
        for k, v in {
            "timeout": args.timeout,
            "jobs": args.jobs,
            "repeat": args.repeat,
            "memout": args.memout,
            "pin": args.pin,
            "build_mode": args.build_mode,
        }.items()
        if v is not None
    }

    suites = Suites()
    if suite_paths:
        if args.program or args.input or args.variant or args.name:
            die("--program, --input, --variant and --name define an ad hoc experiment, not one of a suite")
        for path in suite_paths:
            load_suite(Path.cwd() / path, suites)
        names = list(suites.experiments)
        if args.only:
            names = [n.strip() for n in args.only.split(",") if n.strip()]
            for name in names:
                if name not in suites.experiments:
                    die(f"no experiment '{name}' (have: {', '.join(suites.experiments)})")
        plans = [
            make_plan(
                n,
                suites.experiments[n].source,
                resolve_extends(suites, n),
                suites.experiments[n].defaults,
                cli_settings,
                specs,
                suites.build_sets,
            )
            for n in names
        ]
        run_name = "+".join(p.stem for p in suite_paths)
    else:
        if not args.input:
            die("give a suite, or an ad hoc experiment with --input (and --program)")
        if args.only:
            die("--only selects experiments of suites")
        name = args.name or Path(args.program[0] if args.program else args.input[0]).stem
        if not NAME.fullmatch(name):
            die(f"experiment name '{name}' is not [A-Za-z0-9_.-]+; pass --name")
        plans = [make_plan(name, "command line", adhoc_table(args), [], cli_settings, specs, {})]
        run_name = name

    if args.list:
        resolver = Resolver(dry=True)
        for plan in plans:
            describe(plan, resolver)
        return

    resolver = Resolver()
    builder = Builder(args.force)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    base = ROOT / "results/data" / (args.output_dir or f"{run_name}-{stamp}")
    if suite_paths:
        print(f"[!] Suite run: {os.path.relpath(base, ROOT)}")
    for plan in plans:
        if suite_paths:
            print(f"========== {plan.name} ==========")
        run_plan(plan, base / plan.name if suite_paths else base, resolver, builder, args, suites.files)


if __name__ == "__main__":
    main()
