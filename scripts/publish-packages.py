#!/usr/bin/env python3
"""Plan, verify, or publish the SDK releases in this checkout."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[1]
NPM = "https://registry.npmjs.org"
PYPI = "https://pypi.org"
PYPI_UPLOAD = "https://upload.pypi.org/legacy/"
PUB = "https://pub.dev"
CENTRAL = "https://repo.maven.apache.org/maven2"
PUBLIC = "public"
MAIN = "refs/heads/main"
TAG = "refs/tags/"
STABLE = re.compile(r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")


@dataclass(frozen=True)
class Package:
    path: str
    name: str
    version: str
    registry_url: str = ""
    pub_cli: str = ""

    @property
    def ecosystem(self):
        return self.path.split("/")[0]


def run(*args, cwd=ROOT, env=None):
    print(f"> {cwd.relative_to(ROOT) or '.'}  {' '.join(map(str, args))}", flush=True)
    subprocess.run(args, cwd=cwd, env=env, check=True)


def git(*args):
    return subprocess.check_output(("git", *args), cwd=ROOT, text=True).strip()


def git_object(ref):
    result = subprocess.run(
        ("git", "rev-parse", "--verify", "--quiet", ref),
        cwd=ROOT, text=True, stdout=subprocess.PIPE,
    )
    return result.stdout.strip()


def field(pattern, file):
    match = re.search(pattern, file.read_text(), re.MULTILINE)
    if not match:
        raise ValueError(f"Missing release metadata in {file.relative_to(ROOT)}")
    return match[1]


def discover():
    for file in sorted(ROOT.glob("npm/*/package.json")):
        data = json.loads(file.read_text())
        if not data.get("private"):
            name, version = data["name"], data["version"]
            yield Package(f"npm/{file.parent.name}", name, version,
                          f"{NPM}/{quote(name, safe='')}/{quote(version, safe='')}")
    for file in sorted(ROOT.glob("python/*/pyproject.toml")):
        data = tomllib.loads(file.read_text())["project"]
        name, version = data["name"], data["version"]
        yield Package(f"python/{file.parent.name}", name, version,
                      f"{PYPI}/pypi/{name}/{quote(version, safe='')}/json")
    for file in sorted(ROOT.glob("flutter/*/pubspec.yaml")):
        spec = file.read_text()
        publish_to = re.search(r"^publish_to:[ \t]*(\S+)", spec, re.MULTILINE)
        if publish_to:
            host = publish_to[1].strip("'\"")
            if host == "none":
                continue
            if host.rstrip("/") != PUB:
                raise ValueError(f"{file.parent.name} uses a different pub registry")
        name = field(r"^name:[ \t]*['\"]?([\w]+)", file)
        version = field(r"^version:[ \t]*['\"]?([\w.+-]+)", file)
        cli = "flutter" if re.search(r"^[ \t]+sdk:[ \t]+flutter\b", spec, re.MULTILINE) else "dart"
        yield Package(f"flutter/{file.parent.name}", name, version,
                      f"{PUB}/api/packages/{name}/versions/{quote(version, safe='')}", cli)
    for file in sorted(ROOT.glob("go/*/go.mod")):
        yield Package(f"go/{file.parent.name}", field(r"^module\s+(\S+)", file), "")

    gradle = ROOT / "android/engage/build.gradle.kts"
    version = field(r'^version\s*=\s*"([^"]+)"', gradle)
    if not STABLE.fullmatch(version):
        raise ValueError("android/engage requires a stable release version")
    yield Package("android/engage", "ai.lowco:engage", version,
                  f"{CENTRAL}/ai/lowco/engage/{version}/engage-{version}.pom")
    changelog = ROOT / "ios/engage/CHANGELOG.md"
    version = field(r"^## (\d+\.\d+\.\d+)\s*$", changelog)
    yield Package("ios/engage", "LowcoEngage", version)


def already_published(package):
    try:
        with urlopen(package.registry_url, timeout=20) as response:
            if package.ecosystem == "python":
                formats = {file["packagetype"] for file in json.load(response)["urls"]}
                return {"sdist", "bdist_wheel"} <= formats
            return True
    except HTTPError as error:
        if error.code == 404:
            return False
        raise RuntimeError(f"{package.name}: registry returned HTTP {error.code}") from error
    except (URLError, TimeoutError) as error:
        raise RuntimeError(f"{package.name}: registry lookup failed: {error}") from error


def stable_version(value):
    match = STABLE.fullmatch(value)
    return tuple(map(int, match.groups())) if match else None


def public_refs():
    refs = {}
    for line in git("ls-remote", PUBLIC, MAIN, f"{TAG}*").splitlines():
        commit, ref = line.split()
        refs[ref] = commit
    if MAIN not in refs:
        raise ValueError(f"The {PUBLIC} remote has no main branch")
    return refs


def ref_commit(refs, ref):
    commit = refs.get(f"{ref}^{{}}", refs[ref])
    if not git_object(f"{commit}^{{commit}}"):
        # Fetch objects for comparison without creating local tags.
        git("fetch", "--no-tags", PUBLIC, ref)
    return git("rev-parse", f"{commit}^{{commit}}")


def plan_tag(package, refs, versions):
    paths = [package.path]
    if package.ecosystem == "go":
        prefix = f"{TAG}{package.path}/"
        requested = versions.get(package.path)
        major_suffix = re.search(r"/v([2-9]|[1-9][0-9]+)$", package.name)
        majors = {int(major_suffix[1])} if major_suffix else {0, 1}
    else:
        prefix = TAG
        requested = package.version
        majors = None
        paths.append("Package.swift")

    current = [git_object(f"HEAD:{path}") for path in paths]
    if package.ecosystem == "ios":
        # A preview can see the new root manifest before it is committed.
        current[-1] = git("hash-object", "Package.swift")

    candidates = {}
    for ref in refs:
        if not ref.startswith(prefix):
            continue
        suffix = ref.removeprefix(prefix)
        version = stable_version(suffix)
        if not version or (majors is not None and (not suffix.startswith("v") or version[0] not in majors)):
            continue
        if version in candidates and ref_commit(refs, candidates[version]) != ref_commit(refs, ref):
            raise ValueError(f"{ref.removeprefix(TAG)} conflicts with {candidates[version].removeprefix(TAG)}")
        candidates[version] = ref
    latest = max(candidates, default=None)
    version = stable_version(requested) if requested else latest
    if requested and (not version or (majors is not None and version[0] not in majors)):
        raise ValueError(f"Invalid release version {requested} for {package.name}")
    if version in candidates:
        tagged = ref_commit(refs, candidates[version])
        if all(current) and current == [git_object(f"{tagged}:{path}") for path in paths]:
            print(f"SKIP {candidates[version].removeprefix(TAG)} is already published", flush=True)
            return None
        if requested:
            raise ValueError(f"{candidates[version].removeprefix(TAG)} already points to different source")
    if not requested:
        raise ValueError(f"unreleased source; supply --go-version {package.path} VERSION")
    if latest and version <= latest:
        raise ValueError(f"{requested} must be newer than {candidates[latest].removeprefix(TAG)}")

    target = ref_commit(refs, MAIN)
    if not all(current) or current != [git_object(f"{target}:{path}") for path in paths]:
        raise ValueError(f"sync {', '.join(paths)} to {PUBLIC}/main before tagging")
    tag = f"{prefix}v{requested.removeprefix('v')}"
    print(f"PLAN {tag.removeprefix(TAG)} from {PUBLIC}/main ({target[:12]})", flush=True)
    return f"{target}:{tag}"


def prepare(package, output):
    cwd = ROOT / package.path
    if package.ecosystem == "npm":
        output.mkdir()
        run("npm", "ci", "--include=dev", cwd=cwd)
        run("npm", "run", "prepublishOnly", "--if-present", cwd=cwd)
        run("npm", "pack", "--pack-destination", output, cwd=cwd)
        tarball, = output.glob("*.tgz")
        command = ["npm", "publish", str(tarball), "--access", "public", "--registry", NPM]
        if package.name.startswith("@"):
            command.append(f"--{package.name.split('/')[0]}:registry={NPM}")
        if "-" in package.version.split("+")[0]:
            command.extend(["--tag", "next"])
        return command
    if package.ecosystem == "python":
        run(sys.executable, "-m", "build", "--outdir", output, cwd=cwd)
        artifacts = sorted(output.iterdir())
        run(sys.executable, "-m", "twine", "check", "--strict", *artifacts, cwd=cwd)
        return [sys.executable, "-m", "twine", "upload", "--repository-url", PYPI_UPLOAD,
                "--non-interactive", "--skip-existing", *artifacts]
    if package.ecosystem == "flutter":
        run(package.pub_cli, "pub", "publish", "--dry-run", cwd=cwd,
            env={**os.environ, "PUB_HOSTED_URL": PUB})
        return [package.pub_cli, "pub", "publish", "--force"]
    run("./gradlew", "testDebugUnitTest", "publishToMavenLocal", f"-Dmaven.repo.local={output}", cwd=cwd)
    return ["./gradlew", "publishAndReleaseToMavenCentral"]


def require_clean(commit):
    if git("rev-parse", "HEAD") != commit or git("status", "--porcelain"):
        raise ValueError("Publishing requires the same clean, committed checkout throughout")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Preview releases (the default)")
    mode.add_argument("--check", action="store_true", help="Also build and validate pending releases")
    mode.add_argument("--publish", action="store_true", help="Build, validate, and publish pending releases")
    parser.add_argument("--only", action="append", default=[], metavar="ECOSYSTEM_OR_PATH",
                        help="Limit the release to a directory such as npm or npm/engage (repeatable)")
    parser.add_argument("--go-version", action="append", nargs=2, default=[], metavar=("MODULE_PATH", "VERSION"),
                        help="Version for a Go module with unreleased changes (repeatable)")
    parser.add_argument("--lowco-api", type=Path, default=ROOT.parent / "lowco-api",
                        help="Lowco API checkout for the compatibility gate")
    args = parser.parse_args()

    packages = list(discover())
    groups = {package.ecosystem for package in packages} | {package.path for package in packages}
    for group in args.only:
        if group not in groups:
            parser.error(f"Unknown release selection {group!r}")
    packages = [p for p in packages if not args.only or {p.ecosystem, p.path}.intersection(args.only)]
    versions = dict(args.go_version)
    go_paths = {p.path for p in packages if p.ecosystem == "go"}
    if len(versions) != len(args.go_version) or versions.keys() - go_paths:
        parser.error("Each --go-version must name a different selected Go module, such as go/engage")
    commit = git("rev-parse", "HEAD")
    if args.publish:
        require_clean(commit)

    registry_packages = [p for p in packages if p.registry_url]
    pending = []
    with ThreadPoolExecutor(max_workers=8) as pool:
        for package, published in zip(registry_packages, pool.map(already_published, registry_packages)):
            message = "SKIP" if published else "PLAN"
            print(f"{message} {package.path} ({package.name} {package.version})", flush=True)
            if not published:
                pending.append(package)

    git_packages = [p for p in packages if not p.registry_url]
    tags = {}
    blocked = False
    if git_packages:
        refs = public_refs()
        for package in git_packages:
            try:
                if tag := plan_tag(package, refs, versions):
                    tags[package.path] = tag
            except ValueError as error:
                print(f"BLOCKED {package.path}: {error}", file=sys.stderr, flush=True)
                blocked = True
    if blocked:
        return 1
    if not (args.check or args.publish) or not (pending or tags):
        return 0

    active = {p.path for p in pending} | tags.keys()
    if active.intersection({"go/api", "npm/api", "python/api", "flutter/api"}):
        run("make", "api-compat", "api-check", f"LOWCO_API={args.lowco_api.resolve()}")

    with tempfile.TemporaryDirectory(prefix="lowco-release-") as temporary:
        output = Path(temporary)
        commands = [(p, prepare(p, output / p.path.replace("/", "-"))) for p in pending]
        for path in tags:
            if path.startswith("go/"):
                run("go", "test", "./...", cwd=ROOT / path)
            else:
                run("swift", "test", "--scratch-path", output / "swift")
        if args.publish:
            require_clean(commit)
            for package, command in commands:
                print(f"PUBLISH {package.name} {package.version}", flush=True)
                env = {**os.environ, "PUB_HOSTED_URL": PUB} if package.pub_cli else None
                run(*command, cwd=ROOT / package.path, env=env)
            if tags:
                run("git", "push", "--atomic", PUBLIC, *tags.values())
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"Release stopped: {error}")
