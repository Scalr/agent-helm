#!/usr/bin/env python3
"""Inject artifacthub.io/images into Chart.yaml derived from values.yaml + appVersion.

Each chart declares its images in CHART_IMAGES below by pointing at fields in
values.yaml using dotted paths. The script reads those paths, falls back to
`appVersion` when a tag is empty, and writes a fresh `artifacthub.io/images`
block under `annotations:` (replacing any prior value).

Two shapes are supported per image:
  - Separate `repository_path` + `tag_path` (the Helm convention)
  - `combined_path` pointing at a single `repo:tag` string (some charts use this)

Usage:
  scripts/images-to-ah.py charts/agent-local           # writes Chart.yaml
  scripts/images-to-ah.py charts/agent-local --dry-run # prints to stdout
  scripts/images-to-ah.py charts/agent-local --quiet   # suppress info logs

Exit codes:
  0 - success
  1 - user-facing error (missing files, bad config, unresolvable path)
  2 - argparse usage error

Requires PyYAML (`pip install pyyaml`).
"""

from __future__ import annotations

import argparse
import logging
import pathlib
import re
import sys
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: PyYAML is required. Install with: pip install pyyaml\n")
    raise SystemExit(1)

log = logging.getLogger("images-to-ah")


class ImagesError(RuntimeError):
    """Raised for user-facing errors during image annotation injection."""


@dataclass(frozen=True)
class ImageSpec:
    """Declarative pointer into values.yaml for one image reference.

    Either `combined_path` (single `repo:tag` string) must be set, or both
    `repository_path` and `tag_path` (Helm-style separate fields). When
    `tag_path` resolves to an empty string the chart's `appVersion` is used,
    matching the runtime Helm behavior `tag | default .Chart.AppVersion`.
    """

    name: str
    repository_path: str | None = None
    tag_path: str | None = None
    combined_path: str | None = None


CHART_IMAGES: dict[str, tuple[ImageSpec, ...]] = {
    "agent-local": (
        ImageSpec(
            name="agent-runner",
            repository_path="image.repository",
            tag_path="image.tag",
        ),
    ),
    "agent-job": (
        ImageSpec(
            name="agent",
            repository_path="agent.image.repository",
            tag_path="agent.image.tag",
        ),
        ImageSpec(
            name="runner",
            repository_path="task.runner.image.repository",
            tag_path="task.runner.image.tag",
        ),
    ),
    "agent-k8s": (
        ImageSpec(
            name="agent",
            repository_path="image.repository",
            tag_path="image.tag",
        ),
        ImageSpec(
            name="runner",
            combined_path="agent.container_task_image",
        ),
    ),
}


APP_VERSION_RE: re.Pattern[str] = re.compile(r"^appVersion:\s*(\S+)\s*$", re.MULTILINE)
ANNOTATIONS_HEADER_RE: re.Pattern[str] = re.compile(r"^annotations:\s*$")
IMAGES_KEY_RE: re.Pattern[str] = re.compile(r"^\s+artifacthub\.io/images:\s*")


def read_app_version(chart_yaml: str) -> str:
    """Return Chart.yaml's `appVersion`, stripping a single layer of surrounding quotes."""
    m = APP_VERSION_RE.search(chart_yaml)
    if m is None:
        raise ImagesError("`appVersion:` field not found in Chart.yaml")
    raw = m.group(1)
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in ("'", '"'):
        return raw[1:-1]
    return raw


def yaml_path_get(data: object, path: str) -> object:
    """Walk a dotted path into a nested mapping. Raises KeyError if any step is missing."""
    current: object = data
    walked: list[str] = []
    for part in path.split("."):
        if not isinstance(current, dict):
            raise KeyError(
                f"path {path!r}: expected mapping at {'.'.join(walked) or '<root>'}, got {type(current).__name__}"
            )
        if part not in current:
            raise KeyError(f"path {path!r}: key {part!r} not present")
        current = current[part]
        walked.append(part)
    return current


def resolve_image(spec: ImageSpec, values: dict, app_version: str) -> str:
    """Resolve an ImageSpec to a concrete `repo:tag` string."""
    if spec.combined_path is not None:
        ref = yaml_path_get(values, spec.combined_path)
        if not isinstance(ref, str) or not ref:
            raise ImagesError(
                f"{spec.name}: {spec.combined_path} must be a non-empty string"
            )
        if ":" not in ref:
            raise ImagesError(
                f"{spec.name}: {spec.combined_path}={ref!r} is missing a ':tag' suffix"
            )
        return ref

    if spec.repository_path is None or spec.tag_path is None:
        raise ImagesError(
            f"{spec.name}: must set combined_path or both repository_path and tag_path"
        )
    repo = yaml_path_get(values, spec.repository_path)
    if not isinstance(repo, str) or not repo:
        raise ImagesError(
            f"{spec.name}: repository at {spec.repository_path} is empty or not a string"
        )
    tag_raw = yaml_path_get(values, spec.tag_path)
    tag = "" if tag_raw is None else str(tag_raw)
    if not tag:
        tag = app_version
    return f"{repo}:{tag}"


def render_images_block(
    specs: Iterable[ImageSpec], values: dict, app_version: str, indent: str = "    "
) -> str:
    """Render image references as a YAML block scalar payload."""
    out: list[str] = []
    for spec in specs:
        image_ref = resolve_image(spec, values, app_version)
        out.append(f"{indent}- name: {spec.name}")
        out.append(f"{indent}  image: {image_ref}")
    return "\n".join(out)


def inject_images_annotation(chart_yaml: str, ah_block: str) -> str:
    """Set `artifacthub.io/images` under `annotations:`, replacing any prior value.

    Creates the `annotations:` block if absent.
    """
    lines = chart_yaml.splitlines()
    block_lines = ["  artifacthub.io/images: |", *ah_block.splitlines()]

    ann_idx = next(
        (i for i, line in enumerate(lines) if ANNOTATIONS_HEADER_RE.match(line)),
        None,
    )
    if ann_idx is None:
        return chart_yaml.rstrip() + "\n\nannotations:\n" + "\n".join(block_lines) + "\n"

    end_idx = len(lines)
    for j in range(ann_idx + 1, len(lines)):
        if lines[j] and not lines[j][:1].isspace():
            end_idx = j
            break

    existing_start: int | None = None
    existing_end: int | None = None
    for k in range(ann_idx + 1, end_idx):
        if IMAGES_KEY_RE.match(lines[k]):
            existing_start = k
            key_indent = len(lines[k]) - len(lines[k].lstrip())
            existing_end = k + 1
            while existing_end < end_idx:
                nxt = lines[existing_end]
                if not nxt.strip():
                    existing_end += 1
                    continue
                if len(nxt) - len(nxt.lstrip()) <= key_indent:
                    break
                existing_end += 1
            break

    if existing_start is not None and existing_end is not None:
        new_lines = lines[:existing_start] + block_lines + lines[existing_end:]
    else:
        new_lines = lines[:end_idx] + block_lines + lines[end_idx:]

    trailing_newline = "\n" if chart_yaml.endswith("\n") else ""
    return "\n".join(new_lines) + trailing_newline


def process_chart(chart_dir: pathlib.Path, *, dry_run: bool) -> int:
    """Inject (or preview) artifacthub.io/images for one chart directory."""
    if not chart_dir.is_dir():
        raise ImagesError(f"{chart_dir} is not a directory")
    chart_yaml_path = chart_dir / "Chart.yaml"
    values_yaml_path = chart_dir / "values.yaml"
    if not chart_yaml_path.is_file():
        raise ImagesError(f"{chart_yaml_path} not found")
    if not values_yaml_path.is_file():
        raise ImagesError(f"{values_yaml_path} not found")

    chart_name = chart_dir.name
    specs = CHART_IMAGES.get(chart_name)
    if specs is None:
        raise ImagesError(
            f"no image config registered for chart {chart_name!r} in CHART_IMAGES "
            f"(known: {sorted(CHART_IMAGES)})"
        )

    chart_yaml = chart_yaml_path.read_text(encoding="utf-8")
    loaded = yaml.safe_load(values_yaml_path.read_text(encoding="utf-8"))
    if loaded is None:
        loaded = {}
    if not isinstance(loaded, dict):
        raise ImagesError(f"{values_yaml_path} top-level YAML is not a mapping")

    app_version = read_app_version(chart_yaml)

    try:
        block = render_images_block(specs, loaded, app_version)
    except KeyError as e:
        raise ImagesError(f"{chart_name}: {e}") from None

    if dry_run:
        sys.stdout.write(f"# {len(specs)} image refs for {chart_name} (appVersion={app_version})\n")
        sys.stdout.write("annotations:\n  artifacthub.io/images: |\n")
        sys.stdout.write(block + "\n")
        return 0

    chart_yaml_path.write_text(inject_images_annotation(chart_yaml, block), encoding="utf-8")
    log.info("Injected %d image refs into %s", len(specs), chart_yaml_path)
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Inject artifacthub.io/images into a chart's Chart.yaml.",
    )
    parser.add_argument("chart_dir", type=pathlib.Path, help="path to the chart directory")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the result to stdout instead of writing Chart.yaml",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="suppress informational log messages (warnings/errors still shown)",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.WARNING if args.quiet else logging.INFO,
        format="%(levelname)s: %(message)s",
        stream=sys.stderr,
    )

    try:
        return process_chart(args.chart_dir, dry_run=args.dry_run)
    except ImagesError as e:
        log.error("%s", e)
        return 1
    except OSError as e:
        log.error("%s: %s", type(e).__name__, e)
        return 1
    except yaml.YAMLError as e:
        log.error("YAML error: %s", e)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
