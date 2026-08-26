#!/usr/bin/env node
// Generated schema consistency and immutability check.
//
// `validate-ddg-pixel-defs` regenerates `wide_events/generated_schemas/*.json`
// immediately before this script runs. The generated directory must therefore
// be clean relative to HEAD. This catches both stale tracked schemas and new,
// untracked schemas that were not committed.
//
// Generated schemas are also versioned artifacts. The filename includes the
// composed `<base>.<event_major>.<event_minor>` version, so changing generator
// inputs should produce a new file by bumping the appropriate source version,
// rather than modifying an existing file in place.
//
// There is one safe exception: a branch may commit regenerated output for inputs
// that were already stale on its base branch. If validation leaves the generated
// directory clean and no generation inputs changed on the branch, an in-place
// schema modification is a repair of pre-existing drift rather than a new schema
// change. New (added) files remain valid because they represent new versions.

import { execFileSync } from 'node:child_process';
import path from 'node:path';
import process from 'node:process';

const rootArgument = process.argv[2];
if (!rootArgument) {
    console.error('usage: check_wide_event_schema_immutability.mjs <PixelDefinitions dir>');
    process.exit(2);
}

const ROOT = path.resolve(rootArgument);
const REPO_ROOT = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();

function repoRelative(file) {
    const relative = path.relative(REPO_ROOT, file);
    if (relative.startsWith('..') || path.isAbsolute(relative)) {
        throw new Error(`${file} is outside the Git repository`);
    }
    return relative;
}

const WIDE_EVENTS_DIR = path.join(ROOT, 'wide_events');
const SCHEMAS_DIR = repoRelative(path.join(WIDE_EVENTS_DIR, 'generated_schemas'));
const PROJECT_DIR = path.dirname(ROOT);
const GENERATOR_INPUTS = [
    repoRelative(path.join(WIDE_EVENTS_DIR, 'definitions')),
    repoRelative(path.join(WIDE_EVENTS_DIR, 'base_event.json')),
    repoRelative(path.join(WIDE_EVENTS_DIR, 'props_dictionary.json')),
    repoRelative(path.join(PROJECT_DIR, 'package.json')),
    repoRelative(path.join(PROJECT_DIR, 'package-lock.json')),
    repoRelative(path.join(REPO_ROOT, 'package.json')),
    repoRelative(path.join(REPO_ROOT, 'package-lock.json')),
];

function git(args, options = {}) {
    return execFileSync('git', args, {
        cwd: REPO_ROOT,
        encoding: 'utf8',
        ...options,
    });
}

// Diff base: the merge-base with the PR base branch, so only this branch's
// changes count. Falls back to HEAD (working tree) when the base is unavailable.
function resolveBase() {
    const baseRef = process.env.GITHUB_BASE_REF ? `origin/${process.env.GITHUB_BASE_REF}` : 'origin/main';
    try {
        const mergeBase = git(['merge-base', baseRef, 'HEAD'], { stdio: ['ignore', 'pipe', 'ignore'] }).trim();
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

function lines(output) {
    return output
        .split('\n')
        .map((line) => line.trim())
        .filter(Boolean);
}

function changedPaths(revs, paths, diffFilter) {
    const args = ['diff', '--name-only'];
    if (diffFilter) args.push(`--diff-filter=${diffFilter}`);
    args.push(...revs, '--', ...paths);
    return lines(git(args));
}

function generatedWorkingTreeChanges() {
    return lines(git(['status', '--short', '--untracked-files=all', '--', SCHEMAS_DIR]));
}

let workingTreeChanges;
try {
    workingTreeChanges = generatedWorkingTreeChanges();
} catch (err) {
    console.error(`Could not inspect generated schemas in ${SCHEMAS_DIR}: ${err.message}`);
    process.exit(2);
}

if (workingTreeChanges.length > 0) {
    console.error('Wide-event generated schemas do not match the committed output after validation:');
    for (const change of workingTreeChanges) console.error(`  ${change}`);
    console.error('\nRun the pixel-definition validator and commit every generated schema change, including newly created files.');
    process.exit(1);
}

const base = resolveBase();

let modifiedSchemas;
let changedGeneratorInputs;
try {
    // A modified file existed on the base branch under the same versioned
    // filename. Added schemas are valid new versions and are intentionally
    // excluded from this check.
    modifiedSchemas = changedPaths([base, 'HEAD'], [SCHEMAS_DIR], 'M');
    changedGeneratorInputs = changedPaths([base, 'HEAD'], GENERATOR_INPUTS);
} catch (err) {
    console.error(`Could not compare wide-event schemas with ${base}: ${err.message}`);
    process.exit(2);
}

if (modifiedSchemas.length === 0) {
    console.log('Wide-event generated schema check passed (output is committed and existing versions are unchanged).');
    process.exit(0);
}

if (changedGeneratorInputs.length === 0) {
    console.log('Wide-event generated schema check passed (committed output repairs pre-existing generated-schema drift):');
    for (const file of modifiedSchemas) console.log(`  - ${file}`);
    process.exit(0);
}

console.error('Wide-event generated schemas have been modified in place while schema-generation inputs changed:');
for (const file of modifiedSchemas) console.error(`  - ${file}`);
console.error('Changed schema-generation inputs:');
for (const file of changedGeneratorInputs) console.error(`  - ${file}`);
console.error(
    '\nGenerated schemas are versioned artifacts and must not change content under a fixed filename. Bump the appropriate version in the wide-event source so the regenerator produces a new schema file.',
);
process.exit(1);
