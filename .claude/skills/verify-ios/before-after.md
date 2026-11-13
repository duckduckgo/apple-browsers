# Before and after (bug fixes)

Run the same proof against the base commit (`$V` as in [SKILL.md](SKILL.md), `$proof` your proof, `$dir` an
evidence directory outside the checkout): add a worktree at it and run *this*
checkout's `verify-ios` from inside that worktree. The checkout is taken from the current directory and the skill
from the script's own path, so the base app is built and proved with today's skill and proof, on that worktree's own
simulators. Each report's rerun command starts with `cd` into the checkout it proved:

```bash
base=../base-verify; V="$PWD/$V"                     # absolute, so it still names this checkout's skill from there
git worktree add "$base" "$(git merge-base HEAD origin/main)" && git -C "$base" submodule update --init --recursive
(cd "$base" && $V --device iphone setup && $V build &&
 $V prove "$proof" --devices iphone --evidence-dir "$dir/before")   # expected to fail: the bug
$V prove "$proof" --devices iphone --evidence-dir "$dir/after"      # expected to pass: the fix
(cd "$base" && $V cleanup --all --delete-sims) && git worktree remove --force "$base"   # --force: it has submodules
```
