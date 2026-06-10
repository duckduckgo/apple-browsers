#!/usr/bin/env node
// Schema immutability check.
//
// `validate-ddg-pixel-defs` regenerates `wide_events/generated_schemas/*.json`
// from each `wide_events/definitions/*.json5` source. The filename includes the
// composed `<base>.<event_major>.<event_minor>` version, so any version bump
// produces a brand new file and leaves the previous one alone.
//
// Therefore: a generated schema whose content differs from the PR base branch
// under the SAME filename (a MODIFIED, not added, file) is a sign that someone
// changed the source definition's `feature.data.ext` without bumping
// `meta.version`. That class of change has shipped past the validator before
// (see post-idle-session 1.0.0 incident, May 2026) - the fix is to fail CI here
// so the developer is forced to bump the version, which yields a new filename.
//
// "Modified" is measured against the merge-base with the PR base branch
// (origin/$GITHUB_BASE_REF, else origin/main), so only this branch's changes
// count: a versioned schema that already existed on the base branch cannot be
// edited in place. Comparing against HEAD instead would not catch it, because a
// developer who regenerates in place commits the rewritten schema and the
// working tree then matches HEAD. Falls back to HEAD when no base branch is
// available, e.g. a local run with uncommitted changes. New (added) files are
// fine: they represent a new schema version.

import { execSync } from 'node:child_process';
import path from 'node:path';
import process from 'node:process';

const ROOT = process.argv[2];
if (!ROOT) {
    console.error('usage: check_wide_event_schema_immutability.mjs <PixelDefinitions dir>');
    process.exit(2);
}

const SCHEMAS_DIR = path.join(ROOT, 'wide_events', 'generated_schemas');

// Diff base: the merge-base with the PR base branch, so only this branch's
// changes count. Falls back to HEAD (working tree) when the base is unavailable.
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
            `Wide-event schema immutability check: could not resolve base branch "${baseRef}"; comparing against the working tree only. ` +
                'A full-history checkout (fetch-depth: 0, base branch fetched) is required for this check to see a PR\'s changes.',
        );
    }
    return 'HEAD';
}

let modifiedFiles;
try {
    // --diff-filter=M restricts to in-place modifications (not adds, deletes, renames).
    const out = execSync(`git diff --name-only --diff-filter=M ${resolveBase()} -- ${SCHEMAS_DIR}`, {
        cwd: process.cwd(),
        encoding: 'utf8',
    });
    modifiedFiles = out
        .split('\n')
        .map((f) => f.trim())
        .filter(Boolean);
} catch (err) {
    console.error(`Could not run git diff against ${SCHEMAS_DIR}: ${err.message}`);
    process.exit(2);
}

if (modifiedFiles.length === 0) {
    console.log('Wide-event schema immutability check passed (no in-place modifications).');
    process.exit(0);
}

console.error('Wide-event generated schemas have been modified in place:');
for (const f of modifiedFiles) console.error(`  - ${f}`);
console.error(
    '\nGenerated schemas are versioned artifacts and must not change content under a fixed filename. If you changed a wide-event source definition, bump `meta.version` in the source `.json5` so the regenerator produces a NEW schema file. If you did not intend any change, revert the diff in the generated_schemas/ directory.',
);
process.exit(1);
