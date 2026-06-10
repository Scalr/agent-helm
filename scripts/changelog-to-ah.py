#!/usr/bin/env python3
"""Inject the latest CHANGELOG entries as artifacthub.io/changes into Chart.yaml.

Extracts the change list for the version declared in Chart.yaml, converts it
into Artifact Hub's structured format (list of {kind, description, links?}),
and writes it back into the chart's annotations block (replacing any prior
value of `artifacthub.io/changes`).

Sources, in order of preference:
  - <chart_dir>/RELEASE.md   (snippet produced by the release CI workflow)
  - <chart_dir>/CHANGELOG.md (Keep-a-Changelog format; section selected by chart version)

Section headings map to Artifact Hub `kind` values:
  Added -> added, Changed/Updated/Changes -> changed, Deprecated -> deprecated,
  Removed -> removed, Fixed -> fixed, Security -> security.

Usage:
  scripts/changelog-to-ah.py charts/agent-local           # writes Chart.yaml
  scripts/changelog-to-ah.py charts/agent-local --dry-run # prints to stdout
  scripts/changelog-to-ah.py charts/agent-local --quiet   # suppress info logs

Exit codes:
  0 - success (including no-op when no entries were found)
  1 - user-facing error (missing files, malformed Chart.yaml, I/O errors)
  2 - argparse usage error
"""

from __future__ import annotations

import argparse
import logging
import pathlib
import re
import sys
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

log = logging.getLogger("changelog-to-ah")


class ChangelogError(RuntimeError):
    """Raised for user-facing errors during changelog processing."""


KIND_MAP: dict[str, str] = {
    "added": "added",
    "changed": "changed",
    "updated": "changed",
    "changes": "changed",
    "deprecated": "deprecated",
    "removed": "removed",
    "fixed": "fixed",
    "security": "security",
}

PR_LINK_RE: re.Pattern[str] = re.compile(r"\[#(?P<num>\d+)\]\((?P<url>https?://[^\s)]+)\)")
USER_LINK_RE: re.Pattern[str] = re.compile(r"\[@(?P<user>[\w-]+)\]\((?P<url>https?://[^\s)]+)\)")
VERSION_RE: re.Pattern[str] = re.compile(r"^version:\s*(\S+)\s*$", re.MULTILINE)
SECTION_HEADING_RE: re.Pattern[str] = re.compile(r"^###\s+(\w+)")
BULLET_RE: re.Pattern[str] = re.compile(r"^[-*]\s+(.+)")
ANNOTATIONS_HEADER_RE: re.Pattern[str] = re.compile(r"^annotations:\s*$")
CHANGES_KEY_RE: re.Pattern[str] = re.compile(r"^\s+artifacthub\.io/changes:\s*")


@dataclass(frozen=True)
class Link:
    name: str
    url: str


@dataclass(frozen=True)
class ChangeItem:
    kind: str
    description: str
    links: tuple[Link, ...] = ()


def read_version(chart_yaml: str) -> str:
    """Return the `version:` value from Chart.yaml text.

    Strips a single layer of surrounding single or double quotes so that
    `version: "1.0.0"` and `version: '1.0.0'` resolve the same as `version: 1.0.0`.
    Raises ChangelogError if the field is missing.
    """
    m = VERSION_RE.search(chart_yaml)
    if m is None:
        raise ChangelogError("`version:` field not found in Chart.yaml")
    raw = m.group(1)
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in ("'", '"'):
        return raw[1:-1]
    return raw


def extract_section(changelog: str, version: str) -> str:
    """Return the body of the `## [vX.Y.Z]` or `## [X.Y.Z]` section.

    Returns an empty string if the version section is absent.
    """
    header_re = re.compile(rf"^##\s+\[v?{re.escape(version)}\]")
    other_header_re = re.compile(r"^##\s+\[")
    body: list[str] = []
    in_section = False
    for line in changelog.splitlines():
        if in_section:
            if other_header_re.match(line):
                break
            body.append(line)
        elif header_re.match(line):
            in_section = True
    return "\n".join(body)


def parse_release(text: str) -> list[ChangeItem]:
    """Parse a Keep-a-Changelog snippet into a list of ChangeItem.

    Multi-line bullets are joined into a single description; fenced code
    blocks inside a bullet are dropped (Artifact Hub does not render
    markdown). PR and contributor links are surfaced as `links`.
    """
    items: list[ChangeItem] = []
    current_kind: str = "changed"
    current_lines: list[str] | None = None

    def flush() -> None:
        nonlocal current_lines
        if current_lines is None:
            return
        cleaned: list[str] = []
        for ln in current_lines:
            if ln.strip().startswith("```"):
                break
            cleaned.append(ln.strip())
        body = re.sub(r"\s+", " ", " ".join(s for s in cleaned if s)).strip()
        current_lines = None
        if not body:
            return
        links: list[Link] = []
        for m in PR_LINK_RE.finditer(body):
            links.append(Link(name=f"PR #{m.group('num')}", url=m.group("url")))
        for m in USER_LINK_RE.finditer(body):
            links.append(Link(name=f"@{m.group('user')}", url=m.group("url")))
        items.append(ChangeItem(kind=current_kind, description=body, links=tuple(links)))

    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        heading_match = SECTION_HEADING_RE.match(line)
        if heading_match:
            flush()
            heading = heading_match.group(1).lower()
            if heading in KIND_MAP:
                current_kind = KIND_MAP[heading]
            else:
                log.warning("Unrecognized section heading '%s', defaulting to 'changed'", heading)
                current_kind = "changed"
            continue
        bullet_match = BULLET_RE.match(line)
        if bullet_match:
            flush()
            current_lines = [bullet_match.group(1)]
            continue
        if current_lines is not None:
            if line.startswith(("  ", "\t")) or not line.strip():
                current_lines.append(line)
            else:
                flush()
    flush()
    return items


def yaml_quote(s: str) -> str:
    """Quote a string as a YAML double-quoted scalar (single-line)."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_changes(items: Iterable[ChangeItem], indent: str = "    ") -> str:
    """Render parsed items as a YAML block suitable for `artifacthub.io/changes: |`."""
    out: list[str] = []
    for it in items:
        out.append(f"{indent}- kind: {it.kind}")
        out.append(f"{indent}  description: {yaml_quote(it.description)}")
        if it.links:
            out.append(f"{indent}  links:")
            for link in it.links:
                out.append(f"{indent}    - name: {yaml_quote(link.name)}")
                out.append(f"{indent}      url: {link.url}")
    return "\n".join(out)


def inject_annotation(chart_yaml: str, ah_block: str) -> str:
    """Set the `artifacthub.io/changes` annotation, replacing any prior value.

    Creates an `annotations:` block at the bottom of Chart.yaml if it is missing.
    """
    lines = chart_yaml.splitlines()
    block_lines = ["  artifacthub.io/changes: |", *ah_block.splitlines()]

    ann_idx = next(
        (i for i, line in enumerate(lines) if ANNOTATIONS_HEADER_RE.match(line)),
        None,
    )
    if ann_idx is None:
        return chart_yaml.rstrip() + "\n\nannotations:\n" + "\n".join(block_lines) + "\n"

    # End of the annotations block: first subsequent line that isn't indented (or EOF).
    end_idx = len(lines)
    for j in range(ann_idx + 1, len(lines)):
        if lines[j] and not lines[j][:1].isspace():
            end_idx = j
            break

    existing_start: int | None = None
    existing_end: int | None = None
    for k in range(ann_idx + 1, end_idx):
        if CHANGES_KEY_RE.match(lines[k]):
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


def load_source(chart_dir: pathlib.Path, chart_yaml: str) -> tuple[str, str]:
    """Return (text, label) describing the changelog source to parse.

    Prefers RELEASE.md (the per-version snippet emitted by CI) over CHANGELOG.md.
    Raises ChangelogError if neither file is available.
    """
    release_md = chart_dir / "RELEASE.md"
    if release_md.is_file():
        return release_md.read_text(encoding="utf-8"), release_md.name

    changelog = chart_dir / "CHANGELOG.md"
    if not changelog.is_file():
        raise ChangelogError(
            f"neither {release_md.name} nor {changelog.name} found in {chart_dir}"
        )
    version = read_version(chart_yaml)
    section = extract_section(changelog.read_text(encoding="utf-8"), version)
    if not section.strip():
        log.warning("Version %r not found in %s", version, changelog)
    return section, f"{changelog.name} [{version}]"


def process_chart(chart_dir: pathlib.Path, *, dry_run: bool) -> int:
    """Run the injection (or dry-run preview) for a single chart directory."""
    if not chart_dir.is_dir():
        raise ChangelogError(f"{chart_dir} is not a directory")
    chart_yaml_path = chart_dir / "Chart.yaml"
    if not chart_yaml_path.is_file():
        raise ChangelogError(f"{chart_yaml_path} not found")

    chart_yaml = chart_yaml_path.read_text(encoding="utf-8")
    text, source = load_source(chart_dir, chart_yaml)

    items = parse_release(text)
    if not items:
        log.warning("No changelog entries parsed from %s, skipping", source)
        return 0

    block = render_changes(items)
    plural = "y" if len(items) == 1 else "ies"

    if dry_run:
        sys.stdout.write(f"# {len(items)} entr{plural} from {source}\n")
        sys.stdout.write("annotations:\n  artifacthub.io/changes: |\n")
        sys.stdout.write(block + "\n")
        return 0

    chart_yaml_path.write_text(inject_annotation(chart_yaml, block), encoding="utf-8")
    log.info("Injected %d entr%s from %s into %s", len(items), plural, source, chart_yaml_path)
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Inject CHANGELOG entries as artifacthub.io/changes into a chart's Chart.yaml.",
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
    except ChangelogError as e:
        log.error("%s", e)
        return 1
    except OSError as e:
        log.error("%s: %s", type(e).__name__, e)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
