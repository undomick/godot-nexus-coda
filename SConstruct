#!/usr/bin/env python

import os
import subprocess
import sys

# godot-cpp (see godot-cpp/test/SConstruct pattern)
env = SConscript("godot-cpp/SConstruct")

env.Append(CPPPATH=[env.Dir("src")])
sources = env.Glob("src/*.cpp")

out_dir = "build/extension/bin"

if env["platform"] == "macos":
	library = env.SharedLibrary(
		"{}/libnexus_coda.{}.{}.framework/libnexus_coda.{}.{}".format(
			out_dir, env["platform"], env["target"], env["platform"], env["target"]
		),
		source=sources,
	)
else:
	library = env.SharedLibrary(
		"{}/libnexus_coda{}{}".format(out_dir, env["suffix"], env["SHLIBSUFFIX"]),
		source=sources,
	)

env.NoCache(library)

repo_root = Dir("#").abspath
build_dir_abs = os.path.normpath(os.path.join(repo_root, out_dir))
script_path = os.path.join(repo_root, "scripts", "deploy_addon.py")


def _run_deploy(target, source, env_local):
	subprocess.check_call([sys.executable, script_path, "--build-dir", build_dir_abs], cwd=repo_root)
	with open(str(target[0]), "w", encoding="utf-8") as f:
		f.write("ok\n")
	return None


deploy_stamp = env.Command(
	os.path.join("build", "extension", ".deploy_stamp"),
	library,
	env.Action(_run_deploy, "Deploying addon artifacts to addons/ and project/addons/..."),
)
env.Alias("deploy", deploy_stamp)
env.AlwaysBuild(deploy_stamp)

Default(library)
