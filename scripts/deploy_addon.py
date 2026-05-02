#!/usr/bin/env python3
"""
Copy or symlink built GDExtension binaries from the SCons output directory into:
  - project/addons/nexus_coda/bin (primary / editor tree)
  - addons/nexus_coda/bin (repository-root addon mirror)

Materializes `nexus_coda.gdextension` from `nexus_coda.gdextension.template`, then copies
`plugin.cfg`, `plugin.gd`, and the manifest from `project/addons/nexus_coda` into `addons/nexus_coda`
when the project tree exists.

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


def _resolve_gdextension_template(root: Path) -> Path:
	"""Prefer the project-tree template; fall back to repo-root addon (e.g. CI without project/)."""
	project_tpl = root / "project" / "addons" / "nexus_coda" / "nexus_coda.gdextension.template"
	addon_tpl = root / "addons" / "nexus_coda" / "nexus_coda.gdextension.template"
	if project_tpl.is_file():
		return project_tpl
	if addon_tpl.is_file():
		return addon_tpl
	raise FileNotFoundError(
		f"Missing GDExtension template (expected {project_tpl} or {addon_tpl})"
	)


def _materialize_gdextension_manifest(root: Path) -> None:
	template = _resolve_gdextension_template(root)
	for parent in (
		root / "project" / "addons" / "nexus_coda",
		root / "addons" / "nexus_coda",
	):
		parent.mkdir(parents=True, exist_ok=True)
		out = parent / "nexus_coda.gdextension"
		shutil.copy2(template, out)


def _mirror_plugin_manifest_project_to_addons(root: Path) -> None:
	"""Copy plugin files from the Godot project addon into repo-root addons/ (for commits)."""
	src_dir = root / "project" / "addons" / "nexus_coda"
	if not src_dir.is_dir():
		return
	dst_dir = root / "addons" / "nexus_coda"
	dst_dir.mkdir(parents=True, exist_ok=True)
	for name in ("nexus_coda.gdextension", "plugin.cfg", "plugin.gd"):
		src = src_dir / name
		if src.is_file():
			shutil.copy2(src, dst_dir / name)


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
		root / "project" / "addons" / "nexus_coda" / "bin",
		root / "addons" / "nexus_coda" / "bin",
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

	_materialize_gdextension_manifest(root)
	_mirror_plugin_manifest_project_to_addons(root)
	gdext = root / "addons" / "nexus_coda" / "nexus_coda.gdextension"
	if gdext.is_file():
		print(f"Manifest present -> {gdext}")

	return 0


if __name__ == "__main__":
	sys.exit(main())
