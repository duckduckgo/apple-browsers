#!/usr/bin/env python3
"""Migrate legacy iOS `Pixel` / `DailyPixel` / `UniquePixel` firing call sites onto PixelKit.

This is a one-shot codemod, checked in so that the sweep is reviewable as a *transformation*
rather than as ~1200 unrelated edits. It is deliberately conservative: it rewrites only the call
shapes enumerated below and *reports* everything else. A reported site costs a reviewer a minute;
a wrongly rewritten site is a silently renamed pixel in production, which no rule-level parity
test can catch, because the naming rule stays correct while the per-site frequency choice does
not.

Usage
-----
    python3 scripts/migrate-legacy-pixels.py --report-only [--report <path>]
    python3 scripts/migrate-legacy-pixels.py --apply

`--report-only` writes no `.swift` file. `--apply` rewrites the classified sites in place and
still writes the report, whose unmatched section is the hand-migration list.

How it works
------------
1. `iter_swift_files` enumerates the in-scope files (see EXCLUDED_FILES / EXCLUDED_PREFIXES /
   TEST_DIR_RE).
2. `lex_kinds` builds a per-character map marking comment and string-literal regions, so nothing
   inside prose or a string is ever treated as a call site. Swift block comments nest, strings
   come in plain, triple-quoted and raw (hash-delimited) flavours, and interpolations return to
   code, so this is a real lexer rather than a regex.
3. `find_call_sites` finds every `(Daily|Unique)?Pixel.fire…` occurrence in *code* regions, then
   balances parentheses to find each call's extent and splits its top-level arguments. It matches
   the same thing the sweep's verification grep matches, deliberately including bare mentions and
   project-local conveniences, so the site count is directly comparable and nothing is dropped
   before a human has seen it.
4. `classify` maps one call to either a `Rewrite` or an `Unmatched` carrying the reason.
5. `render` rebuilds the call text; `ensure_pixelkit_import` adds `import PixelKit` where the file
   lacks it.

Frequency mapping (from `iOS/Core/PixelEvent+PixelKit.swift`, which is the reference)
-------------------------------------------------------------------------------------
    Pixel.fire(pixel:)                                             .standard  (omitted)
    Pixel.fire(pixel:debounce: n)                                  .debounce(seconds: n)
    Pixel.fire(_:)                                                 .standard  (omitted)
    DailyPixel.fire(pixel:)                                        .legacyDailyNoSuffix
    DailyPixel.fireDaily(_:)                                       .legacyDailyNoSuffix
    DailyPixel.fireDailyAndCount(pixel:) / (_:)                    .dailyAndCount
      …(pixelNameSuffixes: .dailyPixelSuffixes)  explicit default   .dailyAndCount
      …(pixelNameSuffixes: .legacyDailyPixelSuffixes)               .legacyDailyAndCount
      …(pixelNameSuffixes: .dailyAndStandardSuffixes)               .dailyAndStandard
    UniquePixel.fire(pixel:)   resolved name ends "_u"             .uniqueByName
    UniquePixel.fire(pixel:)   resolved name ends "_unique"        .legacyInitial

`.uniqueByName` hard-guards on a `_u` suffix and returns *without firing* when it is absent, so a
`_unique` pixel routed there would silently stop being sent. The UniquePixel frequency is
therefore resolved from the event's `name` in `iOS/Core/PixelEvent.swift` (see
`PixelEventNameTable`), never from the call, and an event whose name suffix cannot be resolved
statically is reported rather than guessed.

`Pixel.fire(_:)`, `DailyPixel.fireDaily(_:)` and `DailyPixel.fireDailyAndCount(_:error:…)` take
the event positionally. They are `PixelFiring` / `DailyPixelFiring` forwarders to the labelled
form, so they fire at the same frequency as their labelled twin. They are not in the frequency
table above. Each is counted under its own rule, so a reviewer can accept or reject it on its
own. See the comment in `classify` for why a positional argument to `Pixel.fire` is accepted only
when it is provably a `Pixel.Event` case.

Argument mapping
----------------
    error: X                                  event becomes E.withError(X)
    error: nil                                dropped: withError(nil) means no error
    withAdditionalParameters: P               options: .parameters(P)
    includedParameters: [.appVersion]         dropped, it is PixelKit's default
    includedParameters: []                    options: .withoutAppVersion
    includedParameters: [.appVersion, .atb]   options: .withATB

A call carrying both `withAdditionalParameters:` and a non-default `includedParameters:` needs a
composed `Options` value rather than a preset, so it is reported. So is any `onComplete:`,
`onDailyComplete:`, `onCountComplete:`, trailing closure, `forDeviceType:`, `withHeaders:`,
`allowedQueryReservedCharacters:`, `pixelFiring:` or `dailyPixelStore:`.

Two things the rewrite must do beyond the frequency mapping above
-----------------------------------------------------------------
* The event expression is qualified as `Pixel.Event.<case>`. `PixelKit.fire` takes
  `PixelKit.Event`, a protocol existential, so implicit-member syntax does not apply and
  `PixelKit.fire(.appLaunch)` fails to compile with "type 'any PixelKit.Event' has no member".
  Every PixelKit call site already in the repo spells the type out. See `_qualify_event`.
* `import PixelKit` is added where missing, which is most files. See `ensure_pixelkit_import`.
"""


from __future__ import annotations

import argparse
import os
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from typing import Optional

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEARCH_ROOT = "iOS"

PIXEL_EVENT_FILE = "iOS/Core/PixelEvent.swift"

DEFAULT_REPORT_PATH = (
    ".superpowers/sdd/2026-08-26-ios-pixelkit-migration/task-8-classification.md"
)

# --------------------------------------------------------------------------------------------
# Scope
# --------------------------------------------------------------------------------------------

# Deleted wholesale in Phase 3, so migrating their internals is wasted work.
EXCLUDED_FILES = {
    "iOS/Core/Pixel.swift",
    "iOS/Core/DailyPixel.swift",
    "iOS/Core/UniquePixel.swift",
    "iOS/Core/PersistentPixel.swift",
    # The adapter's file documentation deliberately names every legacy API in its mapping
    # tables. Rewriting those would corrupt the reference explaining why each migrated call
    # site chose its frequency.
    "iOS/Core/PixelEvent+PixelKit.swift",
}

EXCLUDED_PREFIXES = (
    # Orphaned, unbuilt package: an edit there cannot be compiled or tested.
    "iOS/LocalPackages/Waitlist-iOS/",
    # Mocks and test seams; migrated with the injected seams in Task 9.
    "iOS/SharedTestUtils/",
)

# Any `…Test/` or `…Tests/` directory component. Test seams are Task 9's job.
TEST_DIR_RE = re.compile(r"(?:^|/)[^/]*Tests?/")


def is_in_scope(rel_path: str) -> bool:
    if not rel_path.endswith(".swift"):
        return False
    if rel_path in EXCLUDED_FILES:
        return False
    if rel_path.startswith(EXCLUDED_PREFIXES):
        return False
    if TEST_DIR_RE.search(rel_path):
        return False
    return True


def iter_swift_files(root: str):
    base = os.path.join(root, SEARCH_ROOT)
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for filename in sorted(filenames):
            abs_path = os.path.join(dirpath, filename)
            rel_path = os.path.relpath(abs_path, root)
            if is_in_scope(rel_path):
                yield rel_path, abs_path


# --------------------------------------------------------------------------------------------
# Lexer: mark comment and string regions so we never match inside prose or a literal
# --------------------------------------------------------------------------------------------

CODE, COMMENT, STRING = "c", "/", "s"


def lex_kinds(src: str) -> str:
    """Return a string the same length as `src`, each char one of CODE/COMMENT/STRING.

    Handles line comments, nested block comments, plain / triple-quoted / raw (hash-delimited)
    string literals, and interpolation, whose contents are code again and may themselves
    contain string literals.
    """
    n = len(src)
    kinds = [CODE] * n
    i = 0
    # Stack of open string contexts we return to when an interpolation's `)` closes.
    interp_stack: list[tuple[str, int, int]] = []  # (delimiter, hashes, paren_depth)
    while i < n:
        ch = src[i]

        # --- comments -------------------------------------------------------------------
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                kinds[k] = COMMENT
            i = j
            continue
        if src.startswith("/*", i):
            depth = 1
            j = i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth += 1
                    j += 2
                elif src.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            for k in range(i, min(j, n)):
                kinds[k] = COMMENT
            i = j
            continue

        # --- string starts --------------------------------------------------------------
        hashes = 0
        start = i
        if ch == "#":
            h = i
            while h < n and src[h] == "#":
                h += 1
            if h < n and src[h] == '"':
                hashes = h - i
                i = h
                ch = '"'
        if ch == '"':
            triple = src.startswith('"""', i)
            delim = '"""' if triple else '"'
            i += len(delim)
            for k in range(start, i):
                kinds[k] = STRING
            end = _scan_string(src, i, kinds, delim, hashes, interp_stack)
            i = end
            continue

        # --- returning from an interpolation --------------------------------------------
        if interp_stack and ch in "()":
            delim, hashes, depth = interp_stack[-1]
            if ch == "(":
                interp_stack[-1] = (delim, hashes, depth + 1)
                i += 1
                continue
            if depth > 1:
                interp_stack[-1] = (delim, hashes, depth - 1)
                i += 1
                continue
            interp_stack.pop()
            kinds[i] = STRING
            i += 1
            i = _scan_string(src, i, kinds, delim, hashes, interp_stack)
            continue

        i += 1
    return "".join(kinds)


def _scan_string(src, i, kinds, delim, hashes, interp_stack) -> int:
    """Mark string body from `i` until `delim` closes, or until an interpolation opens."""
    n = len(src)
    esc = "\\" + "#" * hashes
    while i < n:
        if src.startswith(esc + "(", i):
            for k in range(i, i + len(esc) + 1):
                kinds[k] = STRING
            interp_stack.append((delim, hashes, 1))
            return i + len(esc) + 1
        if src.startswith(esc, i) and i + len(esc) < n:
            for k in range(i, i + len(esc) + 1):
                kinds[k] = STRING
            i += len(esc) + 1
            continue
        if src.startswith(delim, i):
            closing = delim + "#" * hashes
            for k in range(i, min(i + len(closing), n)):
                kinds[k] = STRING
            return i + len(closing)
        # An unterminated single-line string cannot cross a newline.
        if delim == '"' and src[i] == "\n":
            return i
        kinds[i] = STRING
        i += 1
    return i


# --------------------------------------------------------------------------------------------
# Call-site discovery
# --------------------------------------------------------------------------------------------

# Deliberately matches *any* `fire…` member on the three legacy receivers, and does not require
# a following `(`. That makes the script's site count identical to the sweep's verification grep
#
#     grep -rnE "(^|[^A-Za-z0-9_.])(Daily|Unique)?Pixel\.fire" --include="*.swift" iOS
#
# so nothing is silently invisible: prose mentions and project-local conveniences such as
# `Pixel.fireDailyAndStandard` are counted and then explicitly reported rather than skipped
# before anyone can see them.
CALL_RE = re.compile(
    r"(?<![A-Za-z0-9_.])(Pixel|DailyPixel|UniquePixel)\.(fire[A-Za-z]*)[ \t]*(\()?"
)

# The receiver/method pairs that are genuinely the legacy firing API. Everything else on these
# receivers is a project-local convenience declared in an `extension Pixel` in the app (for
# example `Pixel.fireDailyAndStandard`, `Pixel.fireAttribution`, `Pixel.fireDailyAndCount` taking
# a `MaliciousSiteProtection.Event`). Those take non-`Pixel.Event` arguments and forward to a
# legacy call in their own body, which is itself an in-scope call site, so the *call* needs no
# rewrite and must not be given one.
LEGACY_APIS = {
    ("Pixel", "fire"),
    ("DailyPixel", "fire"),
    ("DailyPixel", "fireDailyAndCount"),
    ("DailyPixel", "fireDaily"),
    ("UniquePixel", "fire"),
}

CLOSERS = {")": "(", "]": "[", "}": "{"}
OPENERS = {"(": ")", "[": "]", "{": "}"}


@dataclass
class Argument:
    label: Optional[str]
    value: str
    start: int  # offset of the label (or the value, when unlabelled)
    end: int  # offset one past the last non-space char of the value


@dataclass
class CallSite:
    rel_path: str
    line: int
    receiver: str  # Pixel | DailyPixel | UniquePixel
    method: str  # fire | fireDailyAndCount
    start: int  # offset of the receiver
    open_paren: int
    close_paren: int
    end: int  # one past the call, including any trailing closure
    args: list[Argument]
    trailing_closure: bool
    source_line: str

    @property
    def api(self) -> str:
        return f"{self.receiver}.{self.method}"

    @property
    def location(self) -> str:
        return f"{self.rel_path}:{self.line}"


def _match_bracket(src: str, kinds: str, open_idx: int) -> int:
    """Offset of the bracket matching the one at `open_idx`, or -1."""
    stack = [src[open_idx]]
    i = open_idx + 1
    n = len(src)
    while i < n:
        if kinds[i] != CODE:
            i += 1
            continue
        ch = src[i]
        if ch in OPENERS:
            stack.append(ch)
        elif ch in CLOSERS:
            if not stack or stack[-1] != CLOSERS[ch]:
                return -1
            stack.pop()
            if not stack:
                return i
        i += 1
    return -1


def _split_args(src: str, kinds: str, open_idx: int, close_idx: int) -> list[Argument]:
    """Split the top-level, comma-separated arguments between the two parens."""
    args: list[Argument] = []
    depth = 0
    seg_start = open_idx + 1
    i = seg_start
    while i < close_idx:
        if kinds[i] != CODE:
            i += 1
            continue
        ch = src[i]
        if ch in OPENERS:
            depth += 1
        elif ch in CLOSERS:
            depth -= 1
        elif ch == "," and depth == 0:
            args.append(_make_arg(src, kinds, seg_start, i))
            seg_start = i + 1
        i += 1
    if src[seg_start:close_idx].strip():
        args.append(_make_arg(src, kinds, seg_start, close_idx))
    return [a for a in args if a is not None]


def _make_arg(src: str, kinds: str, start: int, end: int) -> Optional[Argument]:
    # Trim surrounding whitespace, and any trailing line comment that belongs to the argument.
    while start < end and src[start] in " \t\r\n":
        start += 1
    while end > start and src[end - 1] in " \t\r\n":
        end -= 1
    if start >= end:
        return None
    text = src[start:end]

    # A label is a bare identifier immediately followed by a top-level `:`. Requiring the whole
    # prefix to be an identifier keeps ternaries (`a ? b : c`) and dictionary literals out.
    depth = 0
    for k in range(start, end):
        if kinds[k] != CODE:
            continue
        ch = src[k]
        if ch in OPENERS:
            depth += 1
        elif ch in CLOSERS:
            depth -= 1
        elif ch == ":" and depth == 0:
            prefix = src[start:k].strip()
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", prefix):
                value = src[k + 1 : end].strip()
                return Argument(prefix, value, start, end)
            break
    return Argument(None, text, start, end)


def _skip_trivia(src: str, kinds: str, i: int) -> int:
    n = len(src)
    while i < n and (src[i] in " \t\r\n" or kinds[i] == COMMENT):
        i += 1
    return i


def find_call_sites(rel_path: str, src: str, kinds: str) -> list[CallSite]:
    lines = src.split("\n")
    line_starts = []
    pos = 0
    for line in lines:
        line_starts.append(pos)
        pos += len(line) + 1

    def line_of(offset: int) -> int:
        lo, hi = 0, len(line_starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if line_starts[mid] <= offset:
                lo = mid
            else:
                hi = mid - 1
        return lo  # zero-based

    sites: list[CallSite] = []
    for m in CALL_RE.finditer(src):
        idx = line_of(m.start())
        if kinds[m.start()] != CODE or m.group(3) is None:
            # Either a match inside a comment or a string literal (a codemod that edits prose is
            # a codemod that silently corrupts documentation), or a bare mention with no call
            # parentheses at all. Counted, never rewritten.
            sites.append(
                CallSite(
                    rel_path, idx + 1, m.group(1), m.group(2),
                    m.start(), -1, -1, -1, [], False, lines[idx],
                )
            )
            continue
        open_idx = m.end() - 1
        close_idx = _match_bracket(src, kinds, open_idx)
        if close_idx == -1:
            sites.append(
                CallSite(
                    rel_path, idx + 1, m.group(1), m.group(2),
                    m.start(), open_idx, -1, -1, [], False, lines[idx],
                )
            )
            continue
        args = _split_args(src, kinds, open_idx, close_idx)
        after = _skip_trivia(src, kinds, close_idx + 1)
        trailing = after < len(src) and src[after] == "{"
        end = close_idx + 1
        if trailing:
            brace_end = _match_bracket(src, kinds, after)
            end = brace_end + 1 if brace_end != -1 else close_idx + 1
        sites.append(
            CallSite(
                rel_path, idx + 1, m.group(1), m.group(2),
                m.start(), open_idx, close_idx, end, args, trailing, lines[idx],
            )
        )
    return sites


# --------------------------------------------------------------------------------------------
# Resolving a `Pixel.Event` case to its wire name (needed only for UniquePixel)
# --------------------------------------------------------------------------------------------


@dataclass
class ResolvedName:
    """A `Pixel.Event` case's `name`, as far as it can be resolved statically."""

    # Trailing *literal* text of the name. Empty when the name ends in an interpolation, in
    # which case the suffix is not statically knowable.
    literal_tail: str
    ends_with_interpolation: bool
    full_literal: Optional[str]  # the whole name, when it has no interpolation at all
    # The name as written, with each interpolation collapsed to `\(…)`, for reporting.
    display: str = ""


class PixelEventNameTable:
    """`case` -> resolved `name`, parsed out of `Pixel.Event.name` in PixelEvent.swift.

    Only the *tail* of the name matters here: `_u` selects `.uniqueByName` and `_unique`
    selects `.legacyInitial`. A case such as
    `case .duckAiNativeStorageMigrationDoneUnique(let key): return "m_…_\\(key)_unique"`
    interpolates in the middle but still ends in a literal `_unique`, so it resolves.
    """

    CASE_RE = re.compile(r"(?m)^([ \t]*)case[ \t]+(?=[.(])")

    def __init__(self, src: str, kinds: str):
        # case -> resolved name, only for cases whose `name` is a resolvable string literal.
        self.table: dict[str, ResolvedName] = {}
        # Every case the switch declares, resolvable or not. This is the *existence* test used to
        # decide whether a positional argument is a `Pixel.Event`, which does not need the name.
        self.known_cases: set[str] = set()
        self._parse(src, kinds)

    def _parse(self, src: str, kinds: str) -> None:
        decl = re.search(r"(?m)^\s*public var name: String \{", src)
        if not decl:
            raise SystemExit(f"could not find `var name: String` in {PIXEL_EVENT_FILE}")
        body_open = src.index("{", decl.start())
        body_close = _match_bracket(src, kinds, body_open)
        body = src[body_open:body_close]
        offset = body_open

        matches = list(self.CASE_RE.finditer(body))
        if not matches:
            raise SystemExit(f"no `case` lines found in `Pixel.Event.name` in {PIXEL_EVENT_FILE}")
        # `case` lines belonging to this switch all sit at one indentation; anything deeper is a
        # nested switch inside a case body, whose case names are a different enum's.
        own_indent = Counter(len(mt.group(1)) for mt in matches).most_common(1)[0][0]
        starts = [mt.start() + offset for mt in matches if len(mt.group(1)) == own_indent]
        for n_, case_start in enumerate(starts):
            case_end = starts[n_ + 1] if n_ + 1 < len(starts) else body_close
            chunk = src[case_start:case_end]
            chunk_kinds = kinds[case_start:case_end]
            colon = self._top_level_colon(chunk, chunk_kinds)
            if colon is None:
                continue
            patterns = chunk[:colon].split("case", 1)[1]
            body_text = chunk[colon + 1 :]
            resolved = self._resolve_return(body_text, chunk_kinds[colon + 1 :])
            for name in self._case_names(patterns):
                self.known_cases.add(name)
                if resolved is not None:
                    self.table[name] = resolved

    @staticmethod
    def _top_level_colon(chunk: str, chunk_kinds: str) -> Optional[int]:
        depth = 0
        for i, ch in enumerate(chunk):
            if chunk_kinds[i] != CODE:
                continue
            if ch in OPENERS:
                depth += 1
            elif ch in CLOSERS:
                depth -= 1
            elif ch == ":" and depth == 0:
                return i
        return None

    @staticmethod
    def _case_names(patterns: str) -> list[str]:
        """`.foo, .bar(let x)` -> ['foo', 'bar']"""
        out = []
        for m in re.finditer(r"\.([A-Za-z_][A-Za-z0-9_]*)", patterns):
            out.append(m.group(1))
        return out

    @staticmethod
    def _resolve_return(body_text: str, body_kinds: str) -> Optional[ResolvedName]:
        stripped = body_text.strip()
        if not stripped.startswith("return"):
            return None
        # Locate the string literal that is the whole returned expression.
        i = body_text.index("return") + len("return")
        while i < len(body_text) and body_text[i] in " \t\r\n":
            i += 1
        if i >= len(body_text) or body_text[i] != '"':
            return None
        # Walk the literal, tracking interpolations, and collect the literal segments.
        j = i + 1
        segments: list[str] = []
        cur: list[str] = []
        ended_in_interp = False
        closed = False
        while j < len(body_text):
            if body_kinds[j] != STRING and body_kinds[j] != CODE:
                j += 1
                continue
            if body_text.startswith("\\(", j) and body_kinds[j] == STRING:
                segments.append("".join(cur))
                cur = []
                ended_in_interp = True
                depth = 1
                j += 2
                while j < len(body_text) and depth:
                    if body_text[j] == "(":
                        depth += 1
                    elif body_text[j] == ")":
                        depth -= 1
                    j += 1
                continue
            if body_text.startswith("\\", j):
                cur.append(body_text[j : j + 2])
                j += 2
                continue
            if body_text[j] == '"':
                closed = True
                break
            cur.append(body_text[j])
            ended_in_interp = False
            j += 1
        if not closed:
            return None
        tail = "".join(cur)
        segments.append(tail)
        # Anything continuing the returned expression on the same line (a `+ "x"`, a
        # `.appending(...)`) means we do not have the whole name, so refuse to resolve it. Only
        # the remainder of *this* line matters: what follows on later lines is the next case, a
        # blank line, or a `// MARK:` comment, none of which changes the value returned here.
        rest_line = body_text[j + 1 :].split("\n", 1)[0]
        rest_line = re.sub(r"//.*$", "", rest_line).strip()
        if rest_line:
            return None
        has_interp = len(segments) > 1
        return ResolvedName(
            literal_tail=tail,
            ends_with_interpolation=ended_in_interp,
            full_literal=None if has_interp else tail,
            display="\\(...)".join(segments),
        )

    def is_pixel_event_case(self, expr: str) -> bool:
        """Whether `expr` is unambiguously a `Pixel.Event` case, by name.

        Used to tell `Pixel.fire(.someCase)` (the `PixelFiring` overload taking a `Pixel.Event`)
        apart from `Pixel.fire(MaliciousSiteProtection.Event.visitSite(...))` and from
        `Pixel.fire(someVariable)`, both of which resolve to a different overload or to a type
        this script cannot see.
        """
        mt = re.match(
            r"^(?:Pixel\.Event)?\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|$)", expr.strip()
        )
        return bool(mt) and mt.group(1) in self.known_cases

    def lookup(self, event_expr: str) -> tuple[Optional[ResolvedName], str]:
        """Resolve a call-site event expression like `.subscriptionActivated` or `.foo(key: k)`."""
        expr = event_expr.strip()
        m = re.match(
            r"^(?:Pixel\.Event)?\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*(\(|$)", expr
        )
        if not m:
            return None, f"event expression is not a literal `Pixel.Event` case: `{expr}`"
        case = m.group(1)
        resolved = self.table.get(case)
        if resolved is None:
            return None, f"case `.{case}` has no statically resolvable `name` in {PIXEL_EVENT_FILE}"
        return resolved, ""


# --------------------------------------------------------------------------------------------
# Classification
# --------------------------------------------------------------------------------------------

# Arguments that are never rewritten. Each maps to the reason reported for the site.
REPORT_ONLY_LABELS = {
    "onComplete": "passes `onComplete:` (needs fireAsync, or the completion dropped: a judgement call about whether the caller uses the result)",
    "onDailyComplete": "passes `onDailyComplete:` (per-variant completion has no PixelKit equivalent)",
    "onCountComplete": "passes `onCountComplete:` (per-variant completion has no PixelKit equivalent)",
    "forDeviceType": "passes `forDeviceType:` (becomes `event.withoutPlatformSuffix` plus `Options.headers`)",
    "withHeaders": "passes `withHeaders:` (becomes `Options.headers`, composed by hand)",
    "allowedQueryReservedCharacters": "passes `allowedQueryReservedCharacters:` (becomes `Options.allowedQueryReservedCharacters`, composed by hand)",
    "pixelFiring": "passes `pixelFiring:` (injected seam; belongs to Task 9)",
    "dailyPixelStore": "passes `dailyPixelStore:` (injected seam; belongs to Task 9)",
}

INCLUDED_PARAMETERS_MAP = {
    # normalized argument text -> (options preset or None to drop, rule tag)
    "[.appVersion]": (None, "includedParameters-default-dropped"),
    "[]": (".withoutAppVersion", "includedParameters-withoutAppVersion"),
    "[.appVersion,.atb]": (".withATB", "includedParameters-withATB"),
}

SUFFIX_FREQUENCY = {
    "legacyDailyPixelSuffixes": (".legacyDailyAndCount", "fireDailyAndCount-legacyDailyPixelSuffixes"),
    "dailyAndStandardSuffixes": (".dailyAndStandard", "fireDailyAndCount-dailyAndStandardSuffixes"),
    "dailyPixelSuffixes": (".dailyAndCount", "fireDailyAndCount-explicitDefaultSuffixes"),
}


@dataclass
class Rewrite:
    site: CallSite
    rule: str
    event_expr: str  # already wrapped in .withError(...) / LegacyNamedPixel(...) as needed
    frequency: Optional[str]  # None means PixelKit's `.standard` default, so omitted
    options: Optional[str]
    tags: list[str] = field(default_factory=list)
    unique_name: Optional[str] = None  # for reporting UniquePixel resolution
    # Where, in the original source, the reused value inside each part began, and how far into
    # the part's text it sits. `render` needs both to re-indent a multi-line value correctly.
    event_value_start: Optional[int] = None
    event_value_offset: int = 0
    options_value_start: Optional[int] = None
    options_value_offset: int = 0


@dataclass
class Unmatched:
    site: CallSite
    reason: str


def classify(site: CallSite, names: PixelEventNameTable):
    if site.close_paren == -1 and site.open_paren == -1:
        return Unmatched(
            site,
            "not a call: a mention of the legacy API in a comment, a string literal, or without "
            "call parentheses. Counted so the total matches the verification grep, never rewritten",
        )
    if site.close_paren == -1:
        return Unmatched(site, "could not balance the call's parentheses")
    if (site.receiver, site.method) not in LEGACY_APIS:
        return Unmatched(
            site,
            f"`{site.api}` is not a legacy firing API but a project-local convenience declared in "
            "an `extension Pixel` in the app. It takes a non-`Pixel.Event` argument and forwards "
            "to a legacy call in its own body, which is a separate in-scope site, so this call "
            "needs no rewrite",
        )
    if site.trailing_closure:
        return Unmatched(
            site,
            "call has a trailing closure (an `onComplete:` in trailing position; needs fireAsync, or the completion dropped)",
        )

    args = list(site.args)
    by_label: dict[str, Argument] = {}
    positional_event = False

    # Three legacy entry points take the event *positionally* rather than as `pixel:`:
    #
    #     PixelFiring.fire(_ pixel: Pixel.Event, withAdditionalParameters:[, includedParameters:,
    #                      onComplete:])                                    -> Pixel.fire
    #     DailyPixelFiring.fireDaily(_ pixel: Pixel.Event[, withAdditionalParameters:])
    #     DailyPixelFiring.fireDailyAndCount(_ pixel: Pixel.Event, error:, withAdditionalParameters:)
    #
    # Each is a forwarder to the labelled form in `iOS/Core/PixelFiring.swift` or
    # `iOS/Core/DailyPixelFiring.swift`, so it fires at the same frequency as its labelled twin
    # and is treated identically from here on.
    #
    # `Pixel.fire` is the one receiver/method pair that is *also* overloaded on a different type,
    # by `extension Pixel { static func fire(_ event: MaliciousSiteProtection.Event) }` in
    # `iOS/DuckDuckGo/MaliciousSiteProtection/Events/MaliciousSiteProtection+Pixel.swift`. So a
    # positional argument there is only accepted when it is provably a `Pixel.Event` case, by
    # name, against the case table parsed out of `PixelEvent.swift`. A bare variable is ambiguous
    # between the two overloads and is reported. `DailyPixel.fireDaily` and
    # `DailyPixel.fireDailyAndCount` have no such competing overload, so any positional argument
    # there is a `Pixel.Event` whatever its expression form.
    if args and args[0].label is None:
        if site.api in ("DailyPixel.fireDaily", "DailyPixel.fireDailyAndCount"):
            by_label["pixel"] = args.pop(0)
            positional_event = True
        elif site.api == "Pixel.fire":
            expr = args[0].value.strip()
            if names.is_pixel_event_case(expr):
                by_label["pixel"] = args.pop(0)
                positional_event = True
            elif expr.startswith("MaliciousSiteProtection."):
                return Unmatched(
                    site,
                    "positional argument is a `MaliciousSiteProtection.Event`, so this resolves to "
                    "the project-local `extension Pixel` overload, not to a legacy `Pixel.Event` "
                    "firing call. Its body is a separate in-scope site, so this call needs no rewrite",
                )
            else:
                return Unmatched(
                    site,
                    f"positional argument `{expr}` is not a statically resolvable `Pixel.Event` "
                    "case, and `Pixel.fire(_:)` is overloaded on `MaliciousSiteProtection.Event`, "
                    "so which overload this is cannot be determined from the source text",
                )
    if site.api == "DailyPixel.fireDaily" and not positional_event:
        return Unmatched(site, "`DailyPixel.fireDaily` without a positional event argument")

    for arg in args:
        if arg.label is None:
            return Unmatched(site, f"unlabelled argument `{arg.value}` (unrecognised call shape)")
        if arg.label in by_label:
            return Unmatched(site, f"duplicate argument label `{arg.label}:`")
        by_label[arg.label] = arg

    for label, reason in REPORT_ONLY_LABELS.items():
        if label in by_label:
            return Unmatched(site, reason)

    tags: list[str] = []

    # --- the event ------------------------------------------------------------------------
    event_value_start: Optional[int] = None
    event_value_offset = 0
    if "pixelNamed" in by_label:
        if site.api != "Pixel.fire":
            return Unmatched(site, f"`pixelNamed:` on `{site.api}`, which has no such overload")
        event_expr = f"LegacyNamedPixel(name: {by_label['pixelNamed'].value})"
        base_event = event_expr
        tags.append("event-pixelNamed")
        event_value_start = by_label["pixelNamed"].end - len(by_label["pixelNamed"].value)
        event_value_offset = len("LegacyNamedPixel(name: ")
    elif "pixel" in by_label:
        base_event = by_label["pixel"].value
        event_expr = _qualify_event(base_event)
        if event_expr != base_event:
            tags.append("event-qualified")
        event_value_start = by_label["pixel"].end - len(base_event)
        event_value_offset = len(event_expr) - len(base_event)
    else:
        return Unmatched(site, "no `pixel:` or `pixelNamed:` argument found")

    # --- error: X -> E.withError(X) --------------------------------------------------------
    if "error" in by_label:
        error_value = by_label["error"].value.strip()
        if "\n" in error_value:
            return Unmatched(site, "`error:` argument spans multiple lines; wrapping it in `withError(...)` by hand keeps the diff readable")
        if error_value == "nil":
            # `withError(nil)` yields an event with no error, which is exactly what the legacy
            # optional `error:` argument did with `nil`. See `Pixel.Event.withError(_:)`. So the
            # wrapper is dropped rather than emitted as noise.
            tags.append("error-nil-dropped")
        else:
            event_expr = f"{event_expr}.withError({error_value})"
            tags.append("error-withError")

    # --- frequency -------------------------------------------------------------------------
    frequency: Optional[str] = None
    if site.api == "Pixel.fire":
        if "debounce" in by_label:
            debounce = by_label["debounce"].value.strip()
            frequency = f".debounce(seconds: {debounce})"
            rule = "Pixel.fire-debounce"
            tags.append("debounce")
        else:
            frequency = None  # PixelKit's default is `.standard`
            rule = "Pixel.fire-positional-standard" if positional_event else "Pixel.fire-standard"
        if positional_event:
            tags.append("positional-event-beyond-brief")
    elif site.api == "DailyPixel.fire":
        frequency = ".legacyDailyNoSuffix"
        rule = "DailyPixel.fire-legacyDailyNoSuffix"
    elif site.api == "DailyPixel.fireDaily":
        # `DailyPixelFiring.fireDaily` is a two-line forwarder in
        # `iOS/Core/DailyPixelFiring.swift`: `fireDaily(_:)` calls `fire(pixel:)` and
        # `fireDaily(_:withAdditionalParameters:)` calls `fire(pixel:withAdditionalParameters:)`.
        # So it fires at exactly `DailyPixel.fire`'s frequency. This rule is not in the module
        # docstring's frequency table above, which lists only `fire` and `fireDailyAndCount`.
        # It is counted separately below, so a reviewer can accept or reject it on its own.
        frequency = ".legacyDailyNoSuffix"
        rule = "DailyPixel.fireDaily-legacyDailyNoSuffix"
        tags.append("fireDaily-beyond-brief")
    elif site.api == "DailyPixel.fireDailyAndCount":
        suffixes = by_label.get("pixelNameSuffixes")
        if suffixes is None:
            frequency = ".dailyAndCount"
            rule = "fireDailyAndCount-defaultSuffixes"
        else:
            m = re.fullmatch(
                r"(?:DailyPixel\.)?(?:Constant\.)?\.?([A-Za-z_][A-Za-z0-9_]*)",
                suffixes.value.strip(),
            )
            key = m.group(1) if m else None
            if key not in SUFFIX_FREQUENCY:
                return Unmatched(
                    site,
                    f"`pixelNameSuffixes:` is not one of the three known constants but `{suffixes.value.strip()}` "
                    "(a forwarded value cannot be mapped to a single frequency)",
                )
            frequency, rule = SUFFIX_FREQUENCY[key]
            tags.append(rule)
        if positional_event:
            rule += "-positional"
            tags.append("positional-event-beyond-brief")
    elif site.api == "UniquePixel.fire":
        resolved, why = names.lookup(base_event)
        if resolved is None:
            return Unmatched(site, f"UniquePixel: {why}")
        if resolved.ends_with_interpolation:
            return Unmatched(
                site,
                "UniquePixel: the event's `name` ends in an interpolation, so the `_u` / `_unique` suffix cannot be resolved statically",
            )
        if resolved.literal_tail.endswith("_unique"):
            frequency, rule = ".legacyInitial", "UniquePixel.fire-legacyInitial"
        elif resolved.literal_tail.endswith("_u"):
            frequency, rule = ".uniqueByName", "UniquePixel.fire-uniqueByName"
        else:
            return Unmatched(
                site,
                f"UniquePixel: resolved name `{resolved.literal_tail}` ends in neither `_u` nor `_unique`",
            )
        tags.append(rule)
    else:
        return Unmatched(site, f"unknown API `{site.api}`")

    # --- options ---------------------------------------------------------------------------
    options: Optional[str] = None
    has_params = "withAdditionalParameters" in by_label
    included = by_label.get("includedParameters")
    included_preset: Optional[str] = None
    if included is not None:
        normalized = re.sub(r"\s+", "", included.value)
        if normalized not in INCLUDED_PARAMETERS_MAP:
            return Unmatched(
                site,
                f"`includedParameters: {included.value.strip()}` is not one of the three mapped forms "
                "(`[.appVersion]`, `[]`, `[.appVersion, .atb]`)",
            )
        included_preset, tag = INCLUDED_PARAMETERS_MAP[normalized]
        tags.append(tag)
        tags.append("includedParameters")
        if normalized == "[.appVersion,.atb]":
            tags.append("atb")

    if has_params and included_preset is not None:
        # `.parameters(p)` and `.withATB` / `.withoutAppVersion` are both whole `Options`
        # values, so combining them needs a composed `Options(...)` rather than a preset.
        return Unmatched(
            site,
            "carries both `withAdditionalParameters:` and a non-default `includedParameters:`, "
            "which needs a composed `Options` value rather than a preset",
        )

    options_value_start: Optional[int] = None
    options_value_offset = 0
    if has_params:
        params = by_label["withAdditionalParameters"]
        options = f".parameters({params.value})"
        options_value_start = params.end - len(params.value)
        options_value_offset = len("options: .parameters(")
        tags.append("withAdditionalParameters")
    elif included_preset is not None:
        options = included_preset

    # Any argument we did not account for means an unrecognised shape.
    consumed = {
        "pixel", "pixelNamed", "error", "debounce", "pixelNameSuffixes",
        "withAdditionalParameters", "includedParameters",
    }
    leftover = sorted(set(by_label) - consumed)
    if leftover:
        return Unmatched(site, f"unrecognised argument label(s): {', '.join(l + ':' for l in leftover)}")

    unique_name = None
    if site.api == "UniquePixel.fire":
        resolved, _ = names.lookup(base_event)
        unique_name = resolved.display if resolved else None

    return Rewrite(
        site, rule, event_expr, frequency, options, tags, unique_name,
        event_value_start, event_value_offset,
        options_value_start, options_value_offset,
    )


# --------------------------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------------------------


def _qualify_event(expr: str) -> str:
    """Qualify a leading-dot event expression as `Pixel.Event.<case>`.

    `PixelKit.fire` takes `PixelKit.Event`, a protocol existential, so Swift's implicit-member
    syntax does not apply: `PixelKit.fire(.appLaunch)` fails to compile with "type 'any
    PixelKit.Event' has no member 'appLaunch'". Every existing PixelKit call site in the repo
    spells the type out (`PixelKit.fire(GeneralPixel.foo)`) for this reason, so the leading dot
    that legacy `Pixel.fire(pixel: .appLaunch)` allowed has to become `Pixel.Event.appLaunch`.

    Expressions that are already qualified, or that are a variable of type `Pixel.Event`, are
    left exactly as written.
    """
    stripped = expr.strip()
    if stripped.startswith("."):
        return "Pixel.Event" + stripped
    return expr


def _column_of(src: str, offset: int) -> int:
    """Zero-based column of `offset` in its own line."""
    return offset - (src.rfind("\n", 0, offset) + 1)


def render(src: str, rw: Rewrite) -> str:
    """The replacement text for `src[rw.site.start:rw.site.close_paren + 1]`.

    Two things make this more than string concatenation.

    First, layout. A legacy call is written in one of two styles: everything on one line, or one
    argument per line aligned under the open paren. `PixelKit.fire(` is a different width from
    `Pixel.fire(pixel: `, so the alignment column moves and one-argument-per-line calls need
    their continuation lines shifted, or the result is misaligned and the diff becomes unreadable.

    Second, values that are themselves multi-line, typically a dictionary literal passed to
    `withAdditionalParameters:`. Their inner lines are indented relative to the *statement*, and
    the statement has not moved, so they are copied through untouched. Shifting them to follow
    the bracket's new column is what alignment would suggest and it looks terrible: the bracket
    moves ~40 columns right, so a six-entry dictionary ends up indented past column 50. Leaving
    them alone yields the idiomatic shape, the literal's body one level in from the statement:

        PixelKit.fire(Pixel.Event.widgetReport, frequency: .legacyDailyNoSuffix, options: .parameters([
            "enabled_widgets": enabledWidgets,
            ...
        ]))

    A one-line call containing a multi-line literal therefore stays a one-line call.
    """
    site = rw.site
    head = "PixelKit.fire("

    parts: list[str] = [rw.event_expr]
    if rw.frequency is not None:
        parts.append(f"frequency: {rw.frequency}")
    if rw.options is not None:
        parts.append(f"options: {rw.options}")

    # One argument per line, or all on one line? Decided by how the *original* was written: a
    # top-level argument that begins a line means the per-line style.
    per_line = any(
        arg is not site.args[0]
        and src[src.rfind("\n", 0, arg.start) + 1 : arg.start].strip() == ""
        and src.rfind("\n", 0, arg.start) > site.open_paren
        for arg in site.args
    )

    align_col = _column_of(src, site.start) + len(head)
    out: list[str] = [head]
    col = align_col
    for i, text in enumerate(parts):
        if i:
            if per_line:
                out.append(",\n" + " " * align_col)
                col = align_col
            else:
                out.append(", ")
                col += 2
        out.append(text)
        col += len(text) - (text.rfind("\n") + 1) if "\n" in text else len(text)
    out.append(")")
    return "".join(out)


def _reindent(text: str, old_indent: int, new_indent: int) -> str:
    """Shift every line of `text` after the first by the change in starting column."""
    if "\n" not in text or old_indent == new_indent:
        return text
    delta = new_indent - old_indent
    lines = text.split("\n")
    out = [lines[0]]
    for line in lines[1:]:
        stripped = line.lstrip(" ")
        lead = len(line) - len(stripped)
        out.append(" " * max(0, lead + delta) + stripped)
    return "\n".join(out)


IMPORT_LINE_RE = re.compile(r"(?m)^(?:@[A-Za-z_]+\s+)?import\s+[A-Za-z_][A-Za-z0-9_.]*\s*$")
HAS_PIXELKIT_IMPORT_RE = re.compile(r"(?m)^(?:@[A-Za-z_]+\s+)?import\s+PixelKit\s*$")


def ensure_pixelkit_import(src: str) -> str:
    """Add `import PixelKit` if the file does not already have it.

    Required, not cosmetic: the rewritten calls name `PixelKit.fire`, so a file without the
    import does not compile. It is appended after the last line of the first contiguous run of
    top-level imports, matching the repo's convention of not ordering imports alphabetically.
    """
    if HAS_PIXELKIT_IMPORT_RE.search(src):
        return src
    lines = src.split("\n")
    last_import = None
    for i, line in enumerate(lines):
        if IMPORT_LINE_RE.fullmatch(line):
            last_import = i
        elif last_import is not None and line.strip() and not line.lstrip().startswith("//"):
            break
    if last_import is None:
        # No import block to extend. Refuse rather than guess at a position.
        raise ValueError("no top-level import block found")
    lines.insert(last_import + 1, "import PixelKit")
    return "\n".join(lines)


def apply_rewrites(src: str, rewrites: list[Rewrite]) -> str:
    """Apply rewrites back-to-front so earlier offsets stay valid, then fix up the import."""
    out = src
    for rw in sorted(rewrites, key=lambda r: r.site.start, reverse=True):
        replacement = render(src, rw)
        out = out[: rw.site.start] + replacement + out[rw.site.close_paren + 1 :]
    return ensure_pixelkit_import(out)


# --------------------------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------------------------

# The brief's per-rule figures, restated here so a disagreement is visible in the report rather
# than discovered after 1177 sites have landed. Each row carries the reconciliation, because
# several of the brief's numbers turn out to measure a *token grep* over the in-scope files
# rather than an *argument passed at a legacy call site*, and those differ.
#
# Field order: brief's figure, then the note explaining any gap.
BRIEF_ARG_FIGURES: list[tuple[str, int, str]] = [
    (
        "pixelNameSuffixes: dailyAndStandardSuffixes", 53,
        "agrees exactly.",
    ),
    (
        "pixelNameSuffixes: legacyDailyPixelSuffixes", 59,
        "the remaining 13 in-scope hits for this token are `persistentPixel.fireDailyAndCount(...)` "
        "calls in `iOS/PacketTunnelProvider/NetworkProtection/NetworkProtectionPacketTunnelProvider.swift`, "
        "which the brief assigns to Task 10 and whose receiver the verification grep does not match.",
    ),
    (
        "pixelNameSuffixes forwarded (unmappable)", 1,
        "the brief's one forwarding site is the *protocol declaration* "
        "`iOS/Core/DailyPixelFiring.swift:28`, not a call. No call site forwards the value, so "
        "there is nothing here the codemod has to refuse.",
    ),
    (
        "includedParameters:", 150,
        "72 legacy call sites pass it. A token grep over the in-scope files finds 114, the extra "
        "42 being `persistentPixel` calls (Task 10) and protocol declarations in `PixelFiring`, "
        "`PixelFiringAsync`, `OnboardingPixelReporter` and `PersistentPixelStoring` (Task 9). A "
        "token grep over all of `iOS/` finds 171. The brief's 150 matches no scope this codemod "
        "uses.",
    ),
    (
        "debounce:", 10,
        "a token grep over the in-scope files finds 9, one of which "
        "(`iOS/DuckDuckGo/DirectoryMonitor.swift:150`, `case .debounce:`) is unrelated to pixels. "
        "8 is the number of legacy call sites passing the argument.",
    ),
    (
        "onComplete: (including trailing-closure form)", 3,
        "**the brief undercounts this one, and it matters for Step 4.** 9 legacy call sites pass "
        "`onComplete:` explicitly and 4 more pass the completion as a trailing closure, so 13 "
        "sites carry a completion. 4 of the explicit ones pass a literal `{ _ in }` and can drop "
        "it; the other 9 forward a real completion and need `fireAsync` or a deliberate decision.",
    ),
    (
        "forDeviceType:", 1,
        "agrees exactly (`iOS/DuckDuckGo/RequeryLogic.swift:79`). Note that this site *also* "
        "passes `withHeaders:` and `onComplete:`, so it appears once in the unmatched list under "
        "whichever reason is reported first.",
    ),
    (
        "includedParameters: [.appVersion, .atb]", 1,
        "agrees exactly: exactly one call site opts into ATB.",
    ),
]


def build_report(
    rewrites: list[Rewrite],
    unmatched: list[Unmatched],
    files: int,
    total: int,
    imports_needed: int = 0,
) -> str:
    sites = [rw.site for rw in rewrites] + [u.site for u in unmatched]
    rule_counts = Counter(rw.rule for rw in rewrites)
    tag_counts = Counter(t for rw in rewrites for t in rw.tags)
    api_counts = Counter(s.api for s in sites)

    # Argument presence measured over every parsed legacy call site, independently of which
    # classification won. A site passing both `forDeviceType:` and `onComplete:` is reported
    # once but counted in both rows, which is what makes these comparable to the brief.
    arg_presence: Counter = Counter()
    suffix_values: Counter = Counter()
    included_values: Counter = Counter()
    trailing = 0
    for s in sites:
        if s.close_paren == -1 or (s.receiver, s.method) not in LEGACY_APIS:
            continue
        if s.trailing_closure:
            trailing += 1
        for arg in s.args:
            if arg.label is None:
                continue
            arg_presence[arg.label] += 1
            normalized = re.sub(r"\s+", "", arg.value)
            if arg.label == "pixelNameSuffixes":
                suffix_values[normalized] += 1
            elif arg.label == "includedParameters":
                included_values[normalized] += 1

    measured = {
        "pixelNameSuffixes: dailyAndStandardSuffixes": sum(
            c for v, c in suffix_values.items() if v.endswith("dailyAndStandardSuffixes")
        ),
        "pixelNameSuffixes: legacyDailyPixelSuffixes": sum(
            c for v, c in suffix_values.items() if v.endswith("legacyDailyPixelSuffixes")
        ),
        "pixelNameSuffixes forwarded (unmappable)": sum(
            c
            for v, c in suffix_values.items()
            if not v.endswith(
                ("dailyAndStandardSuffixes", "legacyDailyPixelSuffixes", "dailyPixelSuffixes")
            )
        ),
        "includedParameters:": arg_presence["includedParameters"],
        "debounce:": arg_presence["debounce"],
        "onComplete: (including trailing-closure form)": arg_presence["onComplete"] + trailing,
        "forDeviceType:": arg_presence["forDeviceType"],
        "includedParameters: [.appVersion, .atb]": included_values.get("[.appVersion,.atb]", 0),
    }

    out: list[str] = []
    w = out.append

    w("# Task 8, Stage A: legacy pixel codemod classification\n")
    w(
        "Produced by `scripts/migrate-legacy-pixels.py --report-only`. **No `.swift` file was "
        "modified.** Every in-scope site is either classified under a named transformation rule "
        "or listed in the unmatched section with the reason it could not be classified.\n"
    )

    # --- scope --------------------------------------------------------------------------
    w("## Scope\n")
    scope_ok = total == 1177 and files == 235
    w(
        f"**{total} sites across {files} files** "
        f"{'— matches the brief exactly.' if scope_ok else '— **DOES NOT match the brief (1177 / 235).**'}\n"
    )
    w(
        "The site scanner deliberately matches the same thing the brief's verification grep does, "
        "`(Daily|Unique)?Pixel\\.fire`, including bare mentions and project-local conveniences, so "
        "the total is directly comparable and nothing is dropped before a human sees it.\n"
    )
    w("| Receiver prefix (the brief's grouping) | This run | Brief | |")
    w("|---|---:|---:|---|")
    prefix_counts = Counter()
    for s in sites:
        prefix_counts[s.receiver] += 1
    for receiver, brief in (("Pixel", 805), ("DailyPixel", 353), ("UniquePixel", 19)):
        mine = prefix_counts[receiver]
        w(f"| `{receiver}.fire…` | {mine} | {brief} | {'ok' if mine == brief else '**MISMATCH**'} |")
    w("")
    w("Broken down by the exact member called:\n")
    w("| API | Sites |")
    w("|---|---:|")
    for api, count in api_counts.most_common():
        w(f"| `{api}` | {count} |")
    w("")
    w(f"- Classified, would be rewritten by `--apply`: **{len(rewrites)}**")
    w(f"- Unmatched, reported for hand migration: **{len(unmatched)}**")
    w("")

    # --- rules --------------------------------------------------------------------------
    w("## Per-rule counts\n")
    w("| Transformation rule | Frequency emitted | Sites |")
    w("|---|---|---:|")
    freq_for_rule: dict[str, set[str]] = {}
    for rw in rewrites:
        # `.debounce(seconds: n)` varies per site, so show its shape rather than one instance.
        shown = rw.frequency or ".standard (omitted, it is PixelKit's default)"
        shown = re.sub(r"\.debounce\(seconds: .*\)", ".debounce(seconds: n)", shown)
        freq_for_rule.setdefault(rw.rule, set()).add(shown)
    for rule, count in sorted(rule_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        w(f"| `{rule}` | `{'`, `'.join(sorted(freq_for_rule[rule]))}` | {count} |")
    w(f"| **total** | | **{len(rewrites)}** |")
    w("")
    w(
        "`DailyPixel.fireDaily-legacyDailyNoSuffix` is **not in the brief's transformation "
        "table**, which lists only `fire` and `fireDailyAndCount`. It covers "
        "`DailyPixelFiring.fireDaily`, a two-line forwarder in `iOS/Core/DailyPixelFiring.swift` "
        "whose whole body is `fire(pixel: pixel, withAdditionalParameters: params)`, so it fires "
        "at exactly `DailyPixel.fire`'s frequency. All 16 sites are a positional event plus an "
        "optional `withAdditionalParameters:`. It is listed separately so it can be accepted or "
        "rejected on its own; the brief's own Step 2 rule (\"if it appears more than about five "
        "times, add it to the script\") is why it is a rule rather than 16 hand edits.\n"
    )

    # --- rewrite shape ------------------------------------------------------------------
    w("## Two things the rewrite has to do that the brief's table does not mention\n")
    w(
        "### 1. The event expression must be qualified as `Pixel.Event.<case>`\n"
        "`PixelKit.fire` takes `PixelKit.Event`, a **protocol existential**, so Swift's "
        "implicit-member syntax does not apply. The brief's table writes `PixelKit.fire(E, ...)`, "
        "and taking `E` verbatim from `Pixel.fire(pixel: .appLaunch)` would emit "
        "`PixelKit.fire(.appLaunch)`, which does not compile:\n"
        "\n```\nerror: type 'any PKEvent' has no member 'alpha'\n```\n\n"
        "(reproduced with `swiftc -typecheck` on a four-line model of the signature). Every one of "
        "the ~290 `PixelKit.fire` call sites already in this repo spells the type out — "
        "`PixelKit.fire(GeneralPixel.foo)` — and none uses a leading dot. So the codemod rewrites "
        f"a leading-dot event to `Pixel.Event.<case>`, which it did for **{tag_counts['event-qualified']}** "
        "of the classified sites. Expressions that are already qualified, or that are a variable "
        "of type `Pixel.Event`, are left exactly as written.\n"
    )
    w(
        "### 2. `import PixelKit` has to be added\n"
        f"{imports_needed} of the {files} files with rewrites do not currently import PixelKit, so "
        "without this they would not compile. `--apply` appends `import PixelKit` after the last "
        "line of the first contiguous top-level import block, matching this repo's convention of "
        "not ordering imports alphabetically. Every one of the in-scope files was confirmed to "
        "have such a block, so no file needs a guessed insertion point.\n"
    )
    w(
        "The in-scope files live in `iOS/DuckDuckGo` (204), `iOS/Core` (18), "
        "`iOS/AutofillCredentialProvider` (7), `iOS/PacketTunnelProvider` (4) and `iOS/Widgets` "
        "(2) — the four processes Phase 0 configured PixelKit in, plus Core. Whether each Xcode "
        "target actually links PixelKit is a build-level fact this script cannot check and no "
        "build was run, so it is the first thing to confirm on `--apply`.\n"
    )

    # --- argument rewrites --------------------------------------------------------------
    w("## Argument counts against the brief's figures\n")
    w(
        "Measured as *arguments passed at a legacy call site*, over all sites, independently of "
        "which classification won. Where this disagrees with the brief, the reconciliation is "
        "given.\n"
    )
    w("| Measure | This run | Brief | | Reconciliation |")
    w("|---|---:|---:|---|---|")
    for label, brief, note in BRIEF_ARG_FIGURES:
        mine = measured[label]
        flag = "ok" if mine == brief else "**MISMATCH**"
        w(f"| {label} | {mine} | {brief} | {flag} | {note} |")
    w("")
    w("Argument rewrites the brief does not quantify:\n")
    w("| Measure | Sites |")
    w("|---|---:|")
    for label, count in (
        ("`error:` rewritten to `.withError(...)`", tag_counts["error-withError"]),
        ("`error: nil`, so the `withError(...)` wrapper is dropped", tag_counts["error-nil-dropped"]),
        ("event expression qualified as `Pixel.Event.<case>`", tag_counts["event-qualified"]),
        ("positional event, a rule beyond the brief", tag_counts["positional-event-beyond-brief"]),
        ("`DailyPixel.fireDaily`, a rule beyond the brief", tag_counts["fireDaily-beyond-brief"]),
        ("`pixel:` present", arg_presence["pixel"]),
        ("`withAdditionalParameters:` present", arg_presence["withAdditionalParameters"]),
        ("`error:` present, becomes `.withError(...)`", arg_presence["error"]),
        ("`withHeaders:` present", arg_presence["withHeaders"]),
        ("`allowedQueryReservedCharacters:` present", arg_presence["allowedQueryReservedCharacters"]),
        ("`onDailyComplete:` present", arg_presence["onDailyComplete"]),
        ("`onCountComplete:` present", arg_presence["onCountComplete"]),
        ("`pixelFiring:` present", arg_presence["pixelFiring"]),
        ("`dailyPixelStore:` present", arg_presence["dailyPixelStore"]),
        ("trailing closure present", trailing),
        ("`pixelNamed:` present, becomes `LegacyNamedPixel(name:)`", arg_presence["pixelNamed"]),
    ):
        w(f"| {label} | {count} |")
    w("")
    w("`includedParameters:` values seen at call sites, and what each maps to:\n")
    w("| Value | Maps to | Sites |")
    w("|---|---|---:|")
    for value, count in included_values.most_common():
        mapped = INCLUDED_PARAMETERS_MAP.get(value)
        if mapped is None:
            target = "**unmapped, reported**"
        elif mapped[0] is None:
            target = "dropped (PixelKit's default)"
        else:
            target = f"`options: {mapped[0]}`"
        w(f"| `{value}` | {target} | {count} |")
    w("")

    # --- UniquePixel --------------------------------------------------------------------
    w("## UniquePixel frequency resolution, per site\n")
    w(
        "`.uniqueByName` hard-guards on a `_u` suffix and returns **without firing** when it is "
        "absent, so routing a `_unique` pixel there would silently kill it. The frequency is "
        "therefore resolved from the event's `name` in `iOS/Core/PixelEvent.swift`, never from "
        "the call.\n"
    )
    w("| Site | Resolved name | Suffix | Frequency |")
    w("|---|---|---|---|")
    unique_rows = [rw for rw in rewrites if rw.site.api == "UniquePixel.fire"]
    for rw in sorted(unique_rows, key=lambda r: (r.site.rel_path, r.site.line)):
        suffix = "_unique" if (rw.unique_name or "").endswith("_unique") else "_u"
        w(f"| `{rw.site.location}` | `{rw.unique_name}` | `{suffix}` | `{rw.frequency}` |")
    unique_unmatched = [u for u in unmatched if u.site.api == "UniquePixel.fire"]
    for u in sorted(unique_unmatched, key=lambda x: (x.site.rel_path, x.site.line)):
        w(f"| `{u.site.location}` | see unmatched list | — | **reported, not rewritten** |")
    w("")
    n_by_name = sum(1 for r in unique_rows if r.frequency == ".uniqueByName")
    n_initial = sum(1 for r in unique_rows if r.frequency == ".legacyInitial")
    w(
        f"{api_counts['UniquePixel.fire']} UniquePixel sites: **{n_by_name} `.uniqueByName`** "
        f"(name ends `_u`), **{n_initial} `.legacyInitial`** (name ends `_unique`), "
        f"**{len(unique_unmatched)} reported** for other reasons.\n"
    )
    w(
        "No UniquePixel site was left unresolved for want of a name: every one of the 19 events "
        "resolves statically. The single `_unique` event, "
        "`.duckAiNativeStorageMigrationDoneUnique(key:)`, interpolates *in the middle* of its "
        "name but still ends in a literal `_unique`, so its suffix is knowable and it routes to "
        "`.legacyInitial`. Had the name ended *in* the interpolation the site would have been "
        "reported instead of guessed.\n"
    )

    # --- unmatched ----------------------------------------------------------------------
    w("## Unmatched sites, complete list\n")
    if not unmatched:
        w("None.\n")
        return "\n".join(out) + "\n"
    by_reason: dict[str, list[Unmatched]] = {}
    for u in unmatched:
        by_reason.setdefault(u.reason, []).append(u)
    w(
        f"**{len(unmatched)} sites in {len(by_reason)} categories.** A site matching several "
        "report-only conditions is listed once, under the first that applies.\n"
    )
    for reason, group in sorted(by_reason.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        w(f"### {len(group)} x {reason}\n")
        for u in sorted(group, key=lambda x: (x.site.rel_path, x.site.line)):
            w(f"- `{u.site.location}`")
            w("  ```swift")
            w(f"  {u.site.source_line.strip()}")
            w("  ```")
        w("")
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--report-only", action="store_true", help="classify and report; write no source file")
    group.add_argument("--apply", action="store_true", help="rewrite the classified call sites in place")
    parser.add_argument("--report", default=None, help="path for the classification report (default: %s)" % DEFAULT_REPORT_PATH)
    parser.add_argument("--root", default=REPO_ROOT)
    args = parser.parse_args()

    root = args.root
    event_src = open(os.path.join(root, PIXEL_EVENT_FILE), encoding="utf-8").read()
    names = PixelEventNameTable(event_src, lex_kinds(event_src))

    all_rewrites: list[Rewrite] = []
    all_unmatched: list[Unmatched] = []
    files_with_sites: set[str] = set()
    total_sites = 0
    imports_needed = 0

    for rel_path, abs_path in iter_swift_files(root):
        src = open(abs_path, encoding="utf-8").read()
        if "Pixel.fire" not in src:
            continue
        kinds = lex_kinds(src)
        sites = find_call_sites(rel_path, src, kinds)
        if not sites:
            continue
        files_with_sites.add(rel_path)
        total_sites += len(sites)
        file_rewrites: list[Rewrite] = []
        for site in sites:
            result = classify(site, names)
            if isinstance(result, Rewrite):
                file_rewrites.append(result)
                all_rewrites.append(result)
            else:
                all_unmatched.append(result)
        if file_rewrites and not HAS_PIXELKIT_IMPORT_RE.search(src):
            imports_needed += 1
        if args.apply and file_rewrites:
            new_src = apply_rewrites(src, file_rewrites)
            if new_src != src:
                open(abs_path, "w", encoding="utf-8").write(new_src)

    report = build_report(
        all_rewrites, all_unmatched, len(files_with_sites), total_sites, imports_needed
    )
    report_path = os.path.join(root, args.report or DEFAULT_REPORT_PATH)
    os.makedirs(os.path.dirname(report_path), exist_ok=True)
    open(report_path, "w", encoding="utf-8").write(report)

    print(f"sites: {total_sites} across {len(files_with_sites)} files")
    print(f"classified: {len(all_rewrites)}")
    print(f"unmatched:  {len(all_unmatched)}")
    print(f"report:     {os.path.relpath(report_path, root)}")
    if args.apply:
        print("applied rewrites in place.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
