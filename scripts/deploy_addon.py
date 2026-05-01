#!/usr/bin/env python3
"""
Copy or symlink built GDExtension binaries from the SCons output directory into:
  - addons/nexus_coda/bin
  - project/addons/nexus_coda/bin

Default is copy (portable on Windows). Use --symlink on Unix for development.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path


def _repo_root() -> Path:
	return Path(__file__).resolve().parents[1]


def _clear_tree(dst: Path) -> None:
	if dst.is_symlink():
		dst.unlink()
	elif dst.is_dir():
		shutil.rmtree(dst)
	elif dst.exists():
		dst.unlink()


def _deploy_item(src: Path, dst_parent: Path, symlink: bool) -> None:
	name = src.name
	dst = dst_parent / name
	dst_parent.mkdir(parents=True, exist_ok=True)

	if symlink and os.name != "nt":
		if dst.exists() or dst.is_symlink():
			dst.unlink()
		dst.symlink_to(src.resolve(), target_is_directory=src.is_dir())
		return

	_clear_tree(dst)
	if src.is_dir():
		shutil.copytree(src, dst, dirs_exist_ok=False, symlinks=False)
	else:
		shutil.copy2(src, dst)


def _iter_artifacts(build_dir: Path) -> list[Path]:
	if not build_dir.is_dir():
		return []
	out: list[Path] = []
	for p in build_dir.iterdir():
		if not p.exists():
			continue
		name = p.name
		if name.startswith("."):
			continue
		suffix = p.suffix.lower()
		if p.is_dir() and suffix == ".framework":
			out.append(p)
			continue
		if suffix in (".dll", ".so", ".dylib", ".wasm"):
			out.append(p)
			continue
		if name.endswith(".wasm"):
			out.append(p)
			continue
		if name.endswith(".xcframework"):
			out.append(p)
			continue
		if suffix == ".a" and ".ios." in name:
			out.append(p)
	return out


def _sync_gdextension_manifest(root: Path) -> None:
	"""Ensure the demo Project tree has the manifest (bins are deployed separately)."""
	src = root / "addons" / "nexus_coda" / "nexus_coda.gdextension"
	if not src.is_file():
		return
	dst_dir = root / "project" / "addons" / "nexus_coda"
	dst_dir.mkdir(parents=True, exist_ok=True)
	shutil.copy2(src, dst_dir / "nexus_coda.gdextension")


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument(
		"--build-dir",
		type=Path,
		default=_repo_root() / "build" / "extension" / "bin",
		help="SCons SharedLibrary output directory (default: build/extension/bin)",
	)
	parser.add_argument(
		"--symlink",
		action="store_true",
		help="Create symlinks instead of copying (ignored on Windows)",
	)
	args = parser.parse_args()

	root = _repo_root()
	build_dir = args.build_dir if args.build_dir.is_absolute() else (root / args.build_dir).resolve()
	destinations = [
		root / "addons" / "nexus_coda" / "bin",
		root / "project" / "addons" / "nexus_coda" / "bin",
	]

	artifacts = _iter_artifacts(build_dir)
	if not artifacts:
		print(f"ERROR: No extension artifacts found in {build_dir}", file=sys.stderr)
		print("Build first, e.g.: scons platform=<os> target=template_debug generate_bindings=yes", file=sys.stderr)
		return 1

	for dest in destinations:
		for src in artifacts:
			_deploy_item(src, dest, args.symlink)
		print(f"Deployed {len(artifacts)} item(s) -> {dest}")

	_sync_gdextension_manifest(root)
	gdext = root / "project" / "addons" / "nexus_coda" / "nexus_coda.gdextension"
	if gdext.is_file():
		print(f"Synced manifest -> {gdext}")

	return 0


if __name__ == "__main__":
	sys.exit(main())
