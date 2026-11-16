#!/usr/bin/env python3
"""Keeps the agent instruction files lean and current.

Checks AGENTS.md/CLAUDE.md files, project skills and REVIEW*.md:
  - token budgets from budgets.json (estimated from bytes, calibrated against `/context`)
  - every AGENTS.md has a sibling CLAUDE.md that loads it
  - backticked paths, Swift types and skill names still exist in the repo

With --base REF it also reports how the context loaded into every session changed.

Usage: agent_context_check.py [--base REF] [--markdown OUT.md]
"""

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
INSTRUCTION_NAMES = ("AGENTS.md", "CLAUDE.md")
SKILLS_DIR = ".claude/skills"


def git(*args, root):
    return subprocess.run(
        ["git", *args], cwd=root, check=True, capture_output=True, text=True
    ).stdout


# ---------------------------------------------------------------------------
# Reading the tree at a ref (or the working tree)
# ---------------------------------------------------------------------------

@dataclass
class Tree:
    """Agent context files at one ref. `ref=None` reads the working tree."""

    root: Path
    ref: str | None = None
    files: dict = field(default_factory=dict)      # path -> text
    symlinks: dict = field(default_factory=dict)   # path -> link target

    @staticmethod
    def is_context_file(path):
        parts = path.split("/")
        return (parts[-1] in INSTRUCTION_NAMES
                or (len(parts) == 1 and re.fullmatch(r"REVIEW.*\.md", path) is not None)
                or (path.startswith(SKILLS_DIR + "/") and len(parts) == 4 and parts[-1] == "SKILL.md"))

    def load(self):
        if self.ref is None:
            listed = git("ls-files", "--cached", "--others", "--exclude-standard",
                         root=self.root).splitlines()
            for path in sorted(p for p in set(listed) if self.is_context_file(p)):
                full = self.root / path
                if full.is_symlink():
                    self.symlinks[path] = os.readlink(full)
                elif full.is_file():
                    self.files[path] = full.read_text(encoding="utf-8")
        else:
            for line in git("ls-tree", "-r", self.ref, root=self.root).splitlines():
                meta, path = line.split("\t", 1)
                if not self.is_context_file(path):
                    continue
                mode = meta.split()[0]
                blob = git("cat-file", "-p", f"{self.ref}:{path}", root=self.root)
                if mode == "120000":
                    self.symlinks[path] = blob.strip()
                else:
                    self.files[path] = blob
        return self


# ---------------------------------------------------------------------------
# Measuring
# ---------------------------------------------------------------------------

def estimate_tokens(text, bytes_per_token):
    return round(len(text.encode("utf-8")) / bytes_per_token)


def parse_frontmatter(text):
    """Minimal YAML frontmatter reader: top-level scalars and folded/literal blocks."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    values, key, block = {}, None, None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if block is not None and (line.startswith((" ", "\t")) or not line.strip()):
            block.append(line.strip())
            values[key] = " ".join(part for part in block if part)
            continue
        block = None
        match = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if not match:
            continue
        key, value = match.group(1), match.group(2).strip()
        if value in (">", ">-", "|", "|-"):
            block = []
            values[key] = ""
        else:
            values[key] = value.strip("'\"")
    return values


@dataclass
class Item:
    path: str
    kind: str          # root | nested | skill-description | skill-body | review
    tokens: int
    always_loaded: bool


def measure(tree, bytes_per_token):
    items = []
    for path, text in tree.files.items():
        name = Path(path).name
        if name in INSTRUCTION_NAMES:
            # Claude Code loads CLAUDE.md; a CLAUDE.md symlink makes AGENTS.md the content.
            is_root = "/" not in path
            items.append(Item(path, "root" if is_root else "nested",
                              estimate_tokens(text, bytes_per_token), always_loaded=is_root))
        elif name == "SKILL.md":
            meta = parse_frontmatter(text)
            listing = f"{meta.get('name', '')}: {meta.get('description', '')}"
            # Claude Code (2.1.322) leaves skills that only users can invoke out of the model's context.
            model_invocable = meta.get("disable-model-invocation", "").lower() != "true"
            items.append(Item(path, "skill-description",
                              estimate_tokens(listing, bytes_per_token), always_loaded=model_invocable))
            items.append(Item(path, "skill-body",
                              estimate_tokens(text, bytes_per_token), always_loaded=False))
        elif name.startswith("REVIEW"):
            items.append(Item(path, "review",
                              estimate_tokens(text, bytes_per_token), always_loaded=False))
    return items


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check_budgets(items, config):
    budgets, overrides = config["budgets"], config.get("overrides", {})
    errors = []
    for item in items:
        key = f"{item.path}#description" if item.kind == "skill-description" else item.path
        limit = overrides.get(key, budgets[item.kind])
        if item.tokens > limit:
            errors.append(f"{key}: ~{item.tokens} tokens, budget {limit} ({item.kind})")
    total = sum(item.tokens for item in items if item.always_loaded)
    if total > budgets["always-loaded-total"]:
        errors.append(f"always-loaded total: ~{total} tokens, budget {budgets['always-loaded-total']}")
    return errors


def check_claude_links(tree):
    errors = []
    for path in tree.files:
        if Path(path).name != "AGENTS.md":
            continue
        sibling = str(Path(path).with_name("CLAUDE.md")) if "/" in path else "CLAUDE.md"
        target = tree.symlinks.get(sibling)
        imports = "@AGENTS.md" in tree.files.get(sibling, "")
        if target != "AGENTS.md" and not imports:
            errors.append(f"{path}: Claude Code won't load it; add `CLAUDE.md` as a symlink to AGENTS.md")
    return errors


BACKTICK = re.compile(r"`([^`\n]+)`")
FENCE = re.compile(r"^(```|~~~).*?^\1", re.MULTILINE | re.DOTALL)
SWIFT_TYPE = re.compile(r"^[A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+$")
SKILL_NAME = re.compile(r"^/?(ddg-[a-z0-9-]+)$")
AGENT_TOOL_NAMES = {
    "AskUserQuestion", "ExitPlanMode", "EnterPlanMode", "MultiEdit", "NotebookEdit", "SendMessage",
    "TaskCreate", "TaskUpdate", "TaskList", "TaskGet", "TaskStop", "TodoWrite", "ToolSearch",
    "WebFetch", "WebSearch",
}


def classify_span(span):
    """Returns (kind, value) for a backticked span worth checking, else None."""
    span = span.strip()
    if (skill := SKILL_NAME.match(span)) is not None:
        return ("skill", skill.group(1))
    if SWIFT_TYPE.match(type_name := re.sub(r"<.*>$", "", span)):
        return ("type", type_name)
    if span.startswith(("http", "~", "$", "-", "/", "@", "+", "..")) or any(c in span for c in " <>*{}()=|,;'\"#"):
        return None
    path = re.sub(r":\d+(-\d+)?$", "", span.removeprefix("./")).rstrip("/")
    return ("path", path) if "/" in path else None


def referenced_spans(tree):
    """Yields (file, kind, value) for each checkable span outside code fences."""
    for path, text in tree.files.items():
        prose = FENCE.sub("", text)
        for span in BACKTICK.findall(prose):
            if (found := classify_span(span)) is not None:
                yield (path, *found)


DECLARATION_KEYWORDS = ("class", "struct", "enum", "protocol", "actor", "typealias", "macro",
                        "@interface", "@protocol")


def declared_types(names, root):
    """Names from `names` that a Swift or Objective-C declaration in the repo defines."""
    pattern = rf"({'|'.join(DECLARATION_KEYWORDS)})[[:space:]]+({'|'.join(names)})"
    result = subprocess.run(
        ["git", "grep", "--untracked", "-h", "-w", "-E", pattern,
         "--", "*.swift", "*.h", "*.m", "*.mm"],
        cwd=root, capture_output=True, text=True,
    )
    keywords = "|".join(re.escape(k) for k in DECLARATION_KEYWORDS)
    found = re.findall(rf"(?:^|[^\w@])(?:{keywords})\s+(\w+)", result.stdout, re.MULTILINE)
    return set(found) & set(names)


def check_references(tree, root, ignored):
    tracked = git("ls-files", "--cached", "--others", "--exclude-standard",
                  root=root).splitlines()
    tracked_set = set(tracked)
    directories = {str(p) for path in tracked for p in Path(path).parents}
    skills = {Path(p).parent.name for p in tree.files if p.startswith(SKILLS_DIR)}

    def path_exists(value, source):
        candidates = [value, str(Path(source).parent / value)]
        return any(c in tracked_set or c in directories for c in candidates)

    def looks_like_repo_path(value, source):
        # Only paths anchored at the repo root or the referencing file's folder; `Color/32px` is not a path.
        first = value.split("/")[0]
        return first in directories or str(Path(source).parent / first) in directories

    spans = [s for s in referenced_spans(tree) if s[2] not in ignored | AGENT_TOOL_NAMES]
    types = sorted({value for _, kind, value in spans if kind == "type"})
    # Module, package and file names (`BrowserServicesKit`, `SnapshotReferences`) have no declaration.
    path_names = {Path(p).stem for p in tracked} | {Path(d).name for d in directories}
    declared = declared_types(types, root) if types else set()

    errors = []
    for source, kind, value in spans:
        if kind == "path" and looks_like_repo_path(value, source) and not path_exists(value, source):
            errors.append(f"{source}: `{value}` doesn't exist in the repo")
        elif kind == "type" and value not in declared and value not in path_names:
            errors.append(f"{source}: `{value}` isn't declared anywhere in the repo")
        elif kind == "skill" and value not in skills:
            errors.append(f"{source}: skill `{value}` isn't in {SKILLS_DIR}/")
    return sorted(set(errors))


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def label(item):
    return f"{item.path} (description)" if item.kind == "skill-description" else item.path


def render_markdown(head_items, base_items, errors):
    base = {(i.path, i.kind): i.tokens for i in base_items or []}
    head = {(i.path, i.kind): i.tokens for i in head_items}

    def delta(new, old):
        if old is None:
            return "new"
        if new is None:
            return "removed"
        change = new - old
        return f"{change:+d}" if change else "0"

    out = ["## Agent context check", ""]
    out.append("❌ " + f"{len(errors)} problem(s):" if errors else "✅ Budgets and references pass.")
    out += [f"- {e}" for e in errors]
    out.append("")

    always = sorted({k for k, v in {**{(i.path, i.kind): i for i in base_items or []},
                                    **{(i.path, i.kind): i for i in head_items}}.items()
                     if v.always_loaded})
    total_head = sum(head.get(k, 0) for k in always)
    total_base = sum(base.get(k, 0) for k in always)
    out += ["### Loaded into every session", "",
            "| File | Base | This PR | Change |", "|---|---:|---:|---:|"]
    for key in always:
        new, old = head.get(key), base.get(key)
        if base_items is None or new != old:
            name = f"{key[0]} (description)" if key[1] == "skill-description" else key[0]
            change = delta(new, old) if base_items is not None else ""
            out.append(f"| {name} | {old if old is not None else '–'} | {new if new is not None else '–'} | {change} |")
    out.append(f"| **Total** | {total_base if base_items is not None else '–'} | {total_head} | "
               f"{delta(total_head, total_base) if base_items is not None else ''} |")

    on_demand = sorted({k for k in {**base, **head}} - set(always))
    changed = [k for k in on_demand if base_items is not None and head.get(k) != base.get(k)]
    if changed:
        out += ["", "### Loaded on demand (changed files)", "",
                "| File | Base | This PR | Change |", "|---|---:|---:|---:|"]
        for key in changed:
            new, old = head.get(key), base.get(key)
            out.append(f"| {key[0]} ({key[1]}) | {old if old is not None else '–'} | "
                       f"{new if new is not None else '–'} | {delta(new, old)} |")
    out += ["", "Tokens are estimated from file size (bytes ÷ "
            "`bytes_per_token` in `scripts/agent-context-check/budgets.json`). "
            "Over budget? Trim the text, move task-specific steps into a skill, or raise the "
            "budget in that file and explain in the PR which agent mistake the extra text prevents."]
    return "\n".join(out) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", help="git ref to compare the context size against")
    parser.add_argument("--markdown", help="write a Markdown report to this path")
    parser.add_argument("--config", default=str(SCRIPT_DIR / "budgets.json"))
    args = parser.parse_args(argv)

    root = Path(git("rev-parse", "--show-toplevel", root=Path.cwd()).strip())
    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    bytes_per_token = config["bytes_per_token"]

    head = Tree(root).load()
    head_items = measure(head, bytes_per_token)
    base_items = measure(Tree(root, args.base).load(), bytes_per_token) if args.base else None

    errors = (check_budgets(head_items, config)
              + check_claude_links(head)
              + check_references(head, root, set(config.get("ignored_references", []))))

    report = render_markdown(head_items, base_items, errors)
    if args.markdown:
        Path(args.markdown).write_text(report, encoding="utf-8")
    print(report)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
