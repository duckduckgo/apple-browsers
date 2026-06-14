#!/usr/bin/env node
// Consistency check between a wide-event pixel definition and its paired
// wide-event source definition.
//
// A wide event is described by TWO definition files that together define it:
//   - the pixel definition  (pixels/definitions/*.json5)        - declares the
//     wide-event pixel, identified by a single-value `meta.type` enum parameter;
//   - the wide-event source (wide_events/definitions/*.json5)   - declares the
//     schema and generates the validated artifact used by remote validation.
// The two are paired by `meta.type`. A pixel with no source has no schema to
// validate against; a source with no pixel is never emitted.
//
// This pairing is transitional: wide events are migrating to the dedicated
// wide-event JSON format (the source files), and the wide-event pixel definition
// is expected to be retired once that migration completes. Until then this check
// keeps the two halves in step.
//
// This check enforces two rules, both measured against the merge-base with the
// PR base branch so only this branch's work counts:
//
//   1. COMPLETENESS - a wide event must have both halves. Fails when this branch
//      leaves a `meta.type` one-sided in a state it was not already in at the base:
//      a newly one-sided pair, a previously complete pair broken, OR a pre-existing
//      one-sided def flipped to miss its other half (e.g. pixel-only becomes
//      source-only). Pre-existing single-sided definitions (e.g. legacy wide-event
//      pixels with no in-repo source) are grandfathered only while they stay
//      one-sided in the SAME direction, so they can be edited freely and back-filled
//      later without tripping this check.
//
//   2. CO-MODIFICATION - for a pair that was already complete at the base, the
//      two definitions should move together. Fails when exactly one side's
//      definition changed on this branch. Change is detected PER DEFINITION, not
//      per file: only the specific `meta.type`'s parsed object is compared (base
//      vs current), so editing unrelated pixels that merely share a `.json5` file
//      does NOT trigger it. The comparison is on the parsed object, so formatting,
//      key order and comment changes are ignored - only a real change to the
//      definition counts. It does not check that the two changes correspond (that
//      would be field-level validation); it only asks whether each side moved.
//      Back-filling a previously one-sided definition is exempt - completing a
//      pair must not demand re-touching the half that already existed.
//
// The base is the merge-base with the PR base branch (origin/$GITHUB_BASE_REF,
// else origin/main). It falls back to HEAD when no base branch is available, e.g.
// a shallow checkout; in that mode only uncommitted working-tree changes count.

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { execSync } from 'node:child_process';
import JSON5 from 'json5';

const ROOT = process.argv[2];
if (!ROOT) {
    console.error('usage: check_wide_event_consistency.mjs <PixelDefinitions dir>');
    process.exit(2);
}

const PIXELS_DIR = path.join(ROOT, 'pixels', 'definitions');
const WIDE_EVENTS_DIR = path.join(ROOT, 'wide_events', 'definitions');

// cwd is the platform dir (e.g. iOS/). git object paths (ls-tree/show) are
// repo-relative, so run those from the repo root and prefix the cwd-relative
// dirs with the path from the repo root to cwd.
const REPO_ROOT = (() => {
    try {
        return execSync('git rev-parse --show-toplevel', { encoding: 'utf8' }).trim();
    } catch {
        return process.cwd();
    }
})();
const SHOW_PREFIX = (() => {
    try {
        return execSync('git rev-parse --show-prefix', { encoding: 'utf8' }).trim();
    } catch {
        return '';
    }
})();

function repoRel(p) {
    return SHOW_PREFIX ? path.posix.join(SHOW_PREFIX, p) : p;
}

// meta.type values a wide-event pixel declares (single-value enum on meta.type).
function pixelMetaTypes(pixelObj) {
    const out = [];
    for (const param of pixelObj.parameters || []) {
        if (param && typeof param === 'object' && param.key === 'meta.type' && Array.isArray(param.enum)) {
            out.push(...param.enum);
        }
    }
    return out;
}

function readJson5Files(dir) {
    if (!fs.existsSync(dir)) return [];
    return fs
        .readdirSync(dir)
        .filter((f) => f.endsWith('.json5'))
        .map((f) => ({ file: path.join(dir, f), content: JSON5.parse(fs.readFileSync(path.join(dir, f), 'utf8')) }));
}

// Read the *.json5 files of a directory as they existed at a git ref, so the
// base snapshot reflects committed state rather than the working tree. Runs from
// the repo root because git tree paths are repo-relative.
function readJson5FilesAtRef(base, repoRelDir) {
    let listed;
    try {
        listed = execSync(`git ls-tree -r --name-only ${base} -- "${repoRelDir}"`, { cwd: REPO_ROOT, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
    } catch {
        return []; // dir did not exist at base
    }
    const out = [];
    for (const p of listed.split('\n').map((s) => s.trim()).filter((s) => s.endsWith('.json5'))) {
        try {
            const content = JSON5.parse(execSync(`git show "${base}:${p}"`, { cwd: REPO_ROOT, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }));
            out.push({ file: p, content });
        } catch {
            // unreadable or unparseable at base - treat as absent
        }
    }
    return out;
}

// Diff base: the merge-base with the PR base branch, so only this branch's work
// counts. Falls back to HEAD (working tree only) when the base is unavailable.
function resolveBase() {
    const baseRef = process.env.GITHUB_BASE_REF ? `origin/${process.env.GITHUB_BASE_REF}` : 'origin/main';
    try {
        const mergeBase = execSync(`git merge-base ${baseRef} HEAD`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
        if (mergeBase) return mergeBase;
    } catch {
        // base branch not fetched (e.g. a shallow checkout); fall back to the working tree
    }
    if (process.env.CI) {
        console.warn(
            `Wide-event consistency check: could not resolve base branch "${baseRef}"; comparing against the working tree only. ` +
                'A full-history checkout (fetch-depth: 0, base branch fetched) is required for this check to see a PR\'s changes.',
        );
    }
    return 'HEAD';
}

// Pixel/source definition files changed on this branch (cwd-relative paths, to
// match the paths built from ROOT). `git diff` covers tracked adds, modifies,
// deletes and renames; `git ls-files --others` adds untracked files, so a
// brand-new definition is seen when running locally before it is committed.
function changedFiles(base) {
    const tracked = execSync(`git diff --name-only --relative ${base} -- "${PIXELS_DIR}" "${WIDE_EVENTS_DIR}"`, { cwd: process.cwd(), encoding: 'utf8' });
    const untracked = execSync(`git ls-files --others --exclude-standard -- "${PIXELS_DIR}" "${WIDE_EVENTS_DIR}"`, { cwd: process.cwd(), encoding: 'utf8' });
    return new Set([...tracked.split('\n'), ...untracked.split('\n')].map((f) => f.trim()).filter(Boolean));
}

// Deterministic serialization of a parsed value: object keys are sorted (so key
// order is irrelevant) and arrays keep their order. Two definitions with the same
// content but different formatting, key order or comments produce the same string,
// so only a real change to the definition shows up as a difference.
function stableStringify(value) {
    if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
    if (value && typeof value === 'object') {
        return `{${Object.keys(value)
            .sort()
            .map((k) => `${JSON.stringify(k)}:${stableStringify(value[k])}`)
            .join(',')}}`;
    }
    return JSON.stringify(value);
}

// Index a snapshot by meta.type. Records, per type: the source file and pixel
// file(s) that declare it (for existence + error messages), plus a content
// signature of the specific source entry and of the specific pixel definition(s),
// so co-modification can be detected per definition rather than per file.
function buildSnapshot(sourceEntries, pixelEntries) {
    const sourceFileByType = new Map();
    const sourceSigByType = new Map();
    for (const { file, content } of sourceEntries) {
        for (const [key, entry] of Object.entries(content)) {
            const metaType = entry?.meta?.type ?? key;
            sourceFileByType.set(metaType, file);
            sourceSigByType.set(metaType, stableStringify(entry));
        }
    }
    const pixelFilesByType = new Map();
    const pixelObjsByType = new Map();
    for (const { file, content } of pixelEntries) {
        for (const pixelObj of Object.values(content)) {
            for (const metaType of pixelMetaTypes(pixelObj)) {
                if (!pixelFilesByType.has(metaType)) pixelFilesByType.set(metaType, new Set());
                pixelFilesByType.get(metaType).add(file);
                if (!pixelObjsByType.has(metaType)) pixelObjsByType.set(metaType, []);
                pixelObjsByType.get(metaType).push(pixelObj);
            }
        }
    }
    // A type can be declared by more than one pixel object; sort their signatures
    // so the combined signature is independent of file read order.
    const pixelSigByType = new Map();
    for (const [metaType, objs] of pixelObjsByType) {
        pixelSigByType.set(metaType, objs.map(stableStringify).sort().join(''));
    }
    return { sourceFileByType, pixelFilesByType, sourceSigByType, pixelSigByType };
}

// A meta.type is incomplete when one half of the pair is present and the other
// is missing. Returns Map<metaType, 'missing-source' | 'missing-pixel'>.
function incompleteTypes({ sourceFileByType, pixelFilesByType }) {
    const out = new Map();
    for (const metaType of new Set([...sourceFileByType.keys(), ...pixelFilesByType.keys()])) {
        const hasSource = sourceFileByType.has(metaType);
        const hasPixel = pixelFilesByType.has(metaType);
        if (hasSource && !hasPixel) out.set(metaType, 'missing-pixel');
        else if (hasPixel && !hasSource) out.set(metaType, 'missing-source');
    }
    return out;
}

function completeTypes({ sourceFileByType, pixelFilesByType }) {
    const out = new Set();
    for (const metaType of sourceFileByType.keys()) {
        if (pixelFilesByType.has(metaType)) out.add(metaType);
    }
    return out;
}

const base = resolveBase();
const changed = changedFiles(base);

// Fast path: this branch touched no pixel/source definitions, so there is
// nothing it could have broken.
if (changed.size === 0) {
    console.log('Wide-event consistency check passed.');
    process.exit(0);
}

const current = buildSnapshot(readJson5Files(WIDE_EVENTS_DIR), readJson5Files(PIXELS_DIR));
const baseIdx = buildSnapshot(readJson5FilesAtRef(base, repoRel(WIDE_EVENTS_DIR)), readJson5FilesAtRef(base, repoRel(PIXELS_DIR)));

const currentIncomplete = incompleteTypes(current);
const baseIncomplete = incompleteTypes(baseIdx);
const baseComplete = completeTypes(baseIdx);

const completenessErrors = [];
const coModificationErrors = [];

// Rule 1 - completeness: a pair that is one-sided NOW and was not already
// one-sided at the base (so this branch added or broke it).
for (const [metaType, kind] of currentIncomplete) {
    // Grandfather only the *same* one-sided state. A pre-existing pixel-only (or
    // source-only) def stays exempt while it remains pixel-only (or source-only),
    // but flipping it to the other one-sided state - e.g. dropping the pixel and
    // adding a source, leaving an orphan source nothing emits - is a new fault and
    // is flagged.
    if (baseIncomplete.get(metaType) === kind) continue; // unchanged one-sided def, grandfathered
    if (kind === 'missing-source') {
        const pixelFiles = [...current.pixelFilesByType.get(metaType)].join(', ');
        completenessErrors.push({ metaType, kind, present: pixelFiles });
    } else {
        completenessErrors.push({ metaType, kind, present: current.sourceFileByType.get(metaType) });
    }
}

// Rule 2 - co-modification: a pair complete at the base AND still complete now,
// where exactly one side's definition changed on this branch. Change is compared
// per definition (its content signature), so an unrelated edit elsewhere in a
// shared file does not count.
for (const metaType of baseComplete) {
    const sourceFile = current.sourceFileByType.get(metaType);
    const pixelFiles = current.pixelFilesByType.get(metaType);
    if (!sourceFile || !pixelFiles) continue; // no longer complete -> handled by completeness rule
    const sourceChanged = baseIdx.sourceSigByType.get(metaType) !== current.sourceSigByType.get(metaType);
    const pixelChanged = baseIdx.pixelSigByType.get(metaType) !== current.pixelSigByType.get(metaType);
    if (sourceChanged !== pixelChanged) {
        coModificationErrors.push({
            metaType,
            changedSide: sourceChanged ? 'source' : 'pixel',
            sourceFile,
            pixelFiles: [...pixelFiles].join(', '),
        });
    }
}

if (completenessErrors.length === 0 && coModificationErrors.length === 0) {
    console.log('Wide-event consistency check passed.');
    process.exit(0);
}

// Build an explanation aimed at a developer who may not know a wide-event pixel
// has a second, separate schema file (or vice versa).
const lines = [];
lines.push('Wide-event consistency check failed.');
lines.push('');
lines.push('A wide event is defined by TWO files, paired by `meta.type`:');
lines.push('  1. the wide-event PIXEL definition   (pixels/definitions/*.json5)');
lines.push('       declares the pixel, via a parameter { "key": "meta.type", "enum": ["<meta-type>"] };');
lines.push('  2. the wide-event SOURCE definition  (wide_events/definitions/*.json5)');
lines.push('       declares the schema and generates the artifact remote validation checks against.');
lines.push('They describe the same event, so they must both exist and stay in sync.');
lines.push('');
lines.push('NOTE: the dedicated wide-event JSON format (the SOURCE file) is the direction of travel.');
lines.push('Wide-event PIXEL definitions are transitional and will be retired once the migration to the');
lines.push('dedicated format is complete - so the SOURCE is the artifact to invest in. Both files are');
lines.push('still required for now, and this check keeps them in step until the pixel side goes away.');

if (completenessErrors.length > 0) {
    lines.push('');
    lines.push('-- Missing the other half --------------------------------------------------');
    lines.push('This branch added or left a wide event with only one of its two files:');
    lines.push('');
    for (const e of completenessErrors) {
        if (e.kind === 'missing-source') {
            lines.push(`  • meta.type "${e.metaType}" has a wide-event PIXEL but NO wide-event SOURCE.`);
            lines.push(`      pixel definition: ${e.present}`);
            lines.push(`      Fix: add a source under wide_events/definitions/ declaring this wide event, e.g.`);
            lines.push(`           { "<name>": { "description": "...", "owners": ["..."],`);
            lines.push(`               "meta": { "type": "${e.metaType}", "version": "0.0" }, "feature": { ... } } }`);
            lines.push(`      (If this pixel is not meant to be a wide event, remove its "meta.type" parameter instead.)`);
        } else {
            lines.push(`  • meta.type "${e.metaType}" has a wide-event SOURCE but NO wide-event PIXEL.`);
            lines.push(`      source definition: ${e.present}`);
            lines.push(`      Fix: add a pixel under pixels/definitions/ that declares this wide event with a`);
            lines.push(`           parameter { "key": "meta.type", "enum": ["${e.metaType}"] }, so the event is emitted.`);
        }
        lines.push('');
    }
    lines.push('Pre-existing single-sided definitions are ignored, so back-filling the missing half');
    lines.push('of an older definition will pass - only halves added or removed on THIS branch are flagged.');
}

if (coModificationErrors.length > 0) {
    lines.push('');
    lines.push('-- Only one half of the definition changed ---------------------------------');
    lines.push('These wide events already had both halves, but this branch changed the definition on');
    lines.push('only one side. The pixel and source describe the same event, so a change to one almost');
    lines.push('always needs the matching change in the other (and a `meta.version` bump in the source if');
    lines.push('the schema shape changed) to keep the declared schema and the emitted pixel in agreement:');
    lines.push('');
    for (const e of coModificationErrors) {
        const changedFile = e.changedSide === 'source' ? e.sourceFile : e.pixelFiles;
        const untouched = e.changedSide === 'source' ? `pixel definition (${e.pixelFiles})` : `source definition (${e.sourceFile})`;
        lines.push(`  • meta.type "${e.metaType}" - you changed the ${e.changedSide.toUpperCase()} definition but not its paired ${e.changedSide === 'source' ? 'PIXEL' : 'SOURCE'}.`);
        lines.push(`      changed:   ${changedFile}`);
        lines.push(`      unchanged: ${untouched}`);
        lines.push(`      Fix: apply the matching change to the ${untouched}.`);
        lines.push('');
    }
    lines.push('Only this specific definition is compared, so unrelated edits to other pixels in the');
    lines.push('same file do not trigger this. If a real change to this definition genuinely needs no');
    lines.push('matching change on the other side, that is the rare exception to work around.');
}

console.error(lines.join('\n'));
process.exit(1);
