#!/usr/bin/env node
// Lockstep check between a wide-event pixel definition and its paired
// wide-event source definition.
//
// A wide-event pixel definition lives in pixels/definitions/*.json5 and its
// schema source lives in wide_events/definitions/*.json5. The two are paired by
// `meta.type`: the pixel declares it via a single-value enum parameter, and the
// source declares it at the top level.
//
// The two files must change together. This check does NOT inspect field
// contents or report what differs - it only verifies that when a paired
// wide-event pixel definition file changed on this branch, its source file
// changed too. We trust the developer to make the correct edit.
//
// "Changed" is measured against the merge-base with the PR base branch
// (origin/$GITHUB_BASE_REF, else origin/main), so only this branch's changes
// count. Falls back to the working tree (HEAD) when no base branch is available,
// e.g. a local run with uncommitted changes.

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

function readJson5Files(dir) {
    if (!fs.existsSync(dir)) return [];
    return fs
        .readdirSync(dir)
        .filter((f) => f.endsWith('.json5'))
        .map((f) => ({ file: path.join(dir, f), content: JSON5.parse(fs.readFileSync(path.join(dir, f), 'utf8')) }));
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
            `Wide-event lockstep check: could not resolve base branch "${baseRef}"; comparing against the working tree only. ` +
                'A full-history checkout (fetch-depth: 0, base branch fetched) is required for this check to see a PR\'s changes.',
        );
    }
    return 'HEAD';
}

function changedFiles(base) {
    // --relative emits paths relative to cwd (the platform dir), matching the
    // paths built from ROOT. Default filter covers added, modified and renamed files.
    const out = execSync(`git diff --name-only --relative ${base} -- "${PIXELS_DIR}" "${WIDE_EVENTS_DIR}"`, {
        cwd: process.cwd(),
        encoding: 'utf8',
    });
    return new Set(
        out
            .split('\n')
            .map((f) => f.trim())
            .filter(Boolean),
    );
}

// Pair source files and pixel files by meta.type.
const sourceFileByType = new Map();
for (const { file, content } of readJson5Files(WIDE_EVENTS_DIR)) {
    for (const [key, entry] of Object.entries(content)) {
        sourceFileByType.set(entry?.meta?.type ?? key, file);
    }
}

const pixelFilesByType = new Map(); // meta.type -> Set<pixel file>
for (const { file, content } of readJson5Files(PIXELS_DIR)) {
    for (const pixelObj of Object.values(content)) {
        for (const metaType of pixelMetaTypes(pixelObj)) {
            if (!pixelFilesByType.has(metaType)) pixelFilesByType.set(metaType, new Set());
            pixelFilesByType.get(metaType).add(file);
        }
    }
}

const changed = changedFiles(resolveBase());

const errors = [];
for (const [metaType, sourceFile] of sourceFileByType) {
    const pixelFiles = pixelFilesByType.get(metaType);
    if (!pixelFiles) continue; // no paired pixel def yet (gradual adoption) - nothing to enforce
    const sourceChanged = changed.has(sourceFile);
    for (const pixelFile of pixelFiles) {
        const pixelChanged = changed.has(pixelFile);
        if (pixelChanged && !sourceChanged) {
            errors.push(`${pixelFile} changed but its paired wide-event source ${sourceFile} (meta.type "${metaType}") did not.`);
        }
    }
}

if (errors.length > 0) {
    console.error('Wide-event lockstep check failed:');
    for (const e of errors) console.error(`  - ${e}`);
    console.error(
        '\nA wide-event pixel definition and its wide-event source definition must be updated together. ' +
            'Update the missing file to match (bump `meta.version` in the source if the schema shape changed).',
    );
    process.exit(1);
}

console.log('Wide-event lockstep check passed.');
