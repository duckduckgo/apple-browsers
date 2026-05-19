#!/usr/bin/env node
// Cross-link consistency check between wide-event pixel definitions
// (PixelDefinitions/pixels/definitions/*.json5) and wide-event source
// definitions (PixelDefinitions/wide_events/definitions/*.json5).
//
// Pairing key: the pixel def's `meta.type` parameter `enum` value vs. the
// wide-event source's top-level meta.type. Every wide-event pixel already
// declares meta.type with a single-value enum, so no extra annotation is
// needed.
//
// What we check, per paired (pixel, wide-event) pair, under `feature.data.ext.*`:
//   1. Every literal `key` in the pixel def exists in the flattened wide-event source.
//   2. Every leaf key in the wide-event source is covered by either a literal `key`
//      or a `keyPattern` in the pixel def.
//   3. For literal-to-literal matches, the `type` agrees.
//   4. For literal-to-literal matches with string/integer types, the `enum` agrees.
//
// Orphan checks:
//   - A wide-event source with no paired pixel def fails.
//   - A pixel def declaring meta.type but no matching wide-event source is
//     allowed (many wide-event pixels don't have source defs yet); a soft
//     warning is printed.

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
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

// Flatten the `ext` block of a wide-event source schema into leaf entries.
// Each leaf has a scalar `type` (string|integer|number|boolean) plus optional `enum`.
// type:object containers are descended into and not emitted as leaves themselves.
function flattenExt(node, prefix) {
    const out = new Map();
    if (!node || typeof node !== 'object') return out;
    for (const [k, v] of Object.entries(node)) {
        if (!v || typeof v !== 'object') continue;
        const fullKey = `${prefix}.${k}`;
        if (v.type === 'object' && v.properties) {
            for (const [nk, nv] of flattenExt(v.properties, fullKey)) out.set(nk, nv);
        } else if (v.type && v.type !== 'object') {
            out.set(fullKey, { type: v.type, enum: v.enum });
        }
    }
    return out;
}

function extractPixelExtEntries(pixelObj) {
    const literals = new Map(); // key -> { type, enum, source }
    const patterns = []; // { regex, source }
    for (const param of pixelObj.parameters || []) {
        if (typeof param !== 'object' || param === null) continue;
        if (typeof param.key === 'string' && param.key.startsWith('feature.data.ext.')) {
            literals.set(param.key, { type: param.type, enum: param.enum });
        } else if (typeof param.keyPattern === 'string' && param.keyPattern.includes('feature\\.data\\.ext\\.')) {
            try {
                patterns.push({ regex: new RegExp(`^${param.keyPattern}$`), source: param.keyPattern, type: param.type, enum: param.enum });
            } catch {
                // ignore invalid regex; upstream validator will flag it
            }
        }
    }
    return { literals, patterns };
}

function extractPixelMetaType(pixelObj) {
    for (const param of pixelObj.parameters || []) {
        if (typeof param === 'object' && param !== null && param.key === 'meta.type' && Array.isArray(param.enum) && param.enum.length === 1) {
            return param.enum[0];
        }
    }
    return null;
}

function arraysEqualAsSets(a, b) {
    if (!Array.isArray(a) || !Array.isArray(b)) return a === b;
    if (a.length !== b.length) return false;
    const sa = new Set(a);
    return b.every((x) => sa.has(x));
}

const errors = [];
const warnings = [];

const pixelFiles = readJson5Files(PIXELS_DIR);
const wideEventFiles = readJson5Files(WIDE_EVENTS_DIR);

// Build: meta.type -> { source: wide-event def entry, file }
const wideEventByType = new Map();
for (const { file, content } of wideEventFiles) {
    for (const [key, entry] of Object.entries(content)) {
        const metaType = entry?.meta?.type ?? key;
        if (wideEventByType.has(metaType)) {
            errors.push(`duplicate wide-event source definition for meta.type "${metaType}": ${file} and ${wideEventByType.get(metaType).file}`);
        }
        wideEventByType.set(metaType, { entry, file });
    }
}

// Build: meta.type -> { pixelName, pixelObj, file }
const pixelByType = new Map();
for (const { file, content } of pixelFiles) {
    for (const [pixelName, pixelObj] of Object.entries(content)) {
        const metaType = extractPixelMetaType(pixelObj);
        if (!metaType) continue;
        if (pixelByType.has(metaType)) {
            errors.push(
                `duplicate pixel definitions for meta.type "${metaType}": ${file} (${pixelName}) and ${pixelByType.get(metaType).file} (${pixelByType.get(metaType).pixelName})`,
            );
        }
        pixelByType.set(metaType, { pixelName, pixelObj, file });
    }
}

// Every wide-event source must have a matching pixel definition
for (const [metaType, { file }] of wideEventByType) {
    if (!pixelByType.has(metaType)) {
        errors.push(`wide-event source ${file} (meta.type "${metaType}") has no matching pixel definition declaring this meta.type`);
    }
}

// Pixel defs with meta.type but no wide-event source: soft warning (gradual adoption).
for (const [metaType, { file, pixelName }] of pixelByType) {
    if (!wideEventByType.has(metaType)) {
        warnings.push(`pixel ${pixelName} in ${file} declares meta.type "${metaType}" but has no wide-event source definition under wide_events/definitions/`);
    }
}

// For each pair, compare feature.data.ext.* coverage
for (const [metaType, { entry: weEntry, file: weFile }] of wideEventByType) {
    const pixel = pixelByType.get(metaType);
    if (!pixel) continue;
    const weLeaves = flattenExt(weEntry?.feature?.data?.ext, 'feature.data.ext');
    const { literals: pxLiterals, patterns: pxPatterns } = extractPixelExtEntries(pixel.pixelObj);

    // 1. Every pixel literal key must exist in wide-event leaves.
    for (const [pxKey, pxVal] of pxLiterals) {
        if (!weLeaves.has(pxKey)) {
            errors.push(
                `pixel ${pixel.pixelName} (${pixel.file}) declares "${pxKey}" but the wide-event source ${weFile} has no such field`,
            );
            continue;
        }
        const weVal = weLeaves.get(pxKey);
        if (pxVal.type && weVal.type && pxVal.type !== weVal.type) {
            errors.push(
                `type mismatch for "${pxKey}": pixel ${pixel.pixelName} says "${pxVal.type}", wide-event source says "${weVal.type}" (${weFile})`,
            );
        }
        if (pxVal.enum && weVal.enum && !arraysEqualAsSets(pxVal.enum, weVal.enum)) {
            errors.push(
                `enum mismatch for "${pxKey}": pixel ${pixel.pixelName} and wide-event source disagree (${weFile})`,
            );
        }
    }

    // 2. Every wide-event leaf key must be covered by literal or pattern in pixel.
    for (const weKey of weLeaves.keys()) {
        if (pxLiterals.has(weKey)) continue;
        if (pxPatterns.some((p) => p.regex.test(weKey))) continue;
        errors.push(
            `wide-event source ${weFile} declares "${weKey}" but pixel ${pixel.pixelName} (${pixel.file}) has no matching parameter (literal or keyPattern)`,
        );
    }
}

if (warnings.length > 0) {
    console.warn('Wide-event consistency warnings:');
    for (const w of warnings) console.warn(`  - ${w}`);
}

if (errors.length > 0) {
    console.error('\nWide-event consistency errors:');
    for (const e of errors) console.error(`  - ${e}`);
    console.error(
        '\nThe pixel definition and the wide-event source definition disagree on `feature.data.ext.*`. Update both files in lockstep, and bump `meta.version` in the source if the schema shape changed.',
    );
    process.exit(1);
}

console.log(`Wide-event consistency check passed (${wideEventByType.size} paired event(s)).`);
