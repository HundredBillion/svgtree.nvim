#!/usr/bin/env python3
"""Materialize the VS Code Explorer reference fixtures in a temporary directory."""

import argparse
import shutil
from pathlib import Path


HERE = Path(__file__).resolve().parent
LONG_NAME = "src/components/a-very-long-component-name-that-exceeds-the-sidebar-width.test.tsx"
UNICODE_NAME = "docs/日本語 notes.md"


def project(destination: Path, revision: str) -> None:
    shutil.copytree(HERE / "project", destination)
    if revision != "initial":
        (destination / "empty folder").mkdir()
    if revision == "initial":
        (destination / LONG_NAME).unlink()
        (destination / UNICODE_NAME).unlink()
    elif revision == "long-empty":
        (destination / UNICODE_NAME).unlink()


def performance(destination: Path) -> None:
    destination.mkdir(parents=True)
    for index in range(10000):
        (destination / f"entry-{index:05d}.lua").touch()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("project", "performance"))
    parser.add_argument("destination", type=Path)
    parser.add_argument("--revision", choices=("initial", "long-empty", "final"), default="final")
    args = parser.parse_args()
    if args.kind == "project":
        project(args.destination, args.revision)
    else:
        performance(args.destination)


if __name__ == "__main__":
    main()
