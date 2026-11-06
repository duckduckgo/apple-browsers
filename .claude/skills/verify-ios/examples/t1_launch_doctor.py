"""A fresh install of this worktree's build launches, and doctor proves the running binary is that build."""
from verify_ios import steps


def run(ios):
    steps.fresh_start(ios)
    report = ios.doctor()
    build = next(c for c in report["checks"] if c["name"] == "build-is-this-worktree")["detail"]
    ios.check("running binary sha256 == build product sha256",
              build["ok"] and build["runningSha"] == build["expectedSha"] and len(build["runningSha"]) == 64, build)
