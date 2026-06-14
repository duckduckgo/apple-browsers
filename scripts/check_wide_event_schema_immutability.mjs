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
// count: a versioned schema that already existed on the base branch must not be
// edited in place. TWO diffs against that base are unioned, because the preceding
// `validate-ddg-pixel-defs` step regenerates generated_schemas/ in the working
// tree from the committed sources before this check runs:
//   - base vs WORKING TREE catches a source whose `feature.data.ext` shape changed
//     with no `meta.version` bump even if the developer never committed the
//     regenerated schema - regeneration materializes the change in the working tree.
//   - base vs committed HEAD catches a generated schema hand-edited and COMMITTED
//     with no source change - regeneration reverts it in the working tree, hiding it
//     from the first diff, so the committed state must be inspected separately.
// Falls back to HEAD as the base when no base branch is available, e.g. a local run
// with uncommitted changes (the HEAD-vs-HEAD diff is then empty, leaving just the
// working-tree diff). New (added) files are fine: they represent a new schema version.

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

// In-place modifications (--diff-filter=M excludes adds, deletes, renames) between
// the given revs, restricted to the generated_schemas dir. With one rev, git diffs
// that rev against the working tree; with two, it diffs the two revs.
function modifiedSchemas(...revs) {
    const out = execSync(`git diff --name-only --diff-filter=M ${revs.join(' ')} -- ${SCHEMAS_DIR}`, {
        cwd: process.cwd(),
        encoding: 'utf8',
    });
    return out
        .split('\n')
        .map((f) => f.trim())
        .filter(Boolean);
}

const base = resolveBase();

let modifiedFiles;
try {
    // Union of base-vs-working-tree and base-vs-committed-HEAD (see header): the
    // first catches changes the regenerator materializes, the second catches a
    // committed in-place edit the regenerator would scrub from the working tree.
    modifiedFiles = [...new Set([...modifiedSchemas(base), ...modifiedSchemas(base, 'HEAD')])].sort();
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
