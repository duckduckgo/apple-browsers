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
//   2. FORMAT CONSISTENCY - the event-specific payload fields declared by the
//      source must be compatible with the paired pixel parameters. Pixel-only
//      transport/documentation details (for example `channel`, suffixes, owners,
//      triggers and descriptions) are ignored. Source shortcuts and pixel
//      parameter shortcuts are resolved, nested source properties are flattened
//      to their dotted pixel keys, and pixel keyPatterns are honored. Existing
//      inconsistencies are grandfathered by issue kind + field path, but this
//      branch may not introduce a new missing field or incompatible constraint.
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
const PIXEL_PARAMS_FILE = path.join(ROOT, 'pixels', 'params_dictionary.json5');
const WIDE_EVENT_PROPS_FILE = path.join(ROOT, 'wide_events', 'props_dictionary.json');

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

function resolvePixelParameters(pixelObj, paramsDictionary) {
    return (pixelObj.parameters || []).map((param) => (typeof param === 'string' ? paramsDictionary[param] : param)).filter(Boolean);
}

// meta.type values a wide-event pixel declares (single-value enum on meta.type).
function pixelMetaTypes(pixelObj, paramsDictionary) {
    const out = [];
    for (const param of resolvePixelParameters(pixelObj, paramsDictionary)) {
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

function readJson5File(file) {
    if (!fs.existsSync(file)) return {};
    return JSON5.parse(fs.readFileSync(file, 'utf8'));
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

function readJson5FileAtRef(base, repoRelFile) {
    try {
        return JSON5.parse(execSync(`git show "${base}:${repoRelFile}"`, { cwd: REPO_ROOT, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }));
    } catch {
        return {};
    }
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

// Pixel/source definition and dictionary files changed on this branch
// (cwd-relative paths, to match the paths built from ROOT). `git diff` covers
// tracked adds, modifies, deletes and renames; `git ls-files --others` adds
// untracked files, so a brand-new definition is seen locally before it is committed.
function changedFiles(base) {
    const tracked = execSync(
        `git diff --name-only --relative ${base} -- "${PIXELS_DIR}" "${WIDE_EVENTS_DIR}" "${PIXEL_PARAMS_FILE}" "${WIDE_EVENT_PROPS_FILE}"`,
        { cwd: process.cwd(), encoding: 'utf8' },
    );
    const untracked = execSync(
        `git ls-files --others --exclude-standard -- "${PIXELS_DIR}" "${WIDE_EVENTS_DIR}" "${PIXEL_PARAMS_FILE}" "${WIDE_EVENT_PROPS_FILE}"`,
        { cwd: process.cwd(), encoding: 'utf8' },
    );
    return new Set([...tracked.split('\n'), ...untracked.split('\n')].map((f) => f.trim()).filter(Boolean));
}

// Deterministic serialization used when sorting schema values such as enums.
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

// Index a snapshot by meta.type. Keep the actual definitions so their payload
// contracts can be compared rather than merely checking whether both files moved.
function buildSnapshot(sourceEntries, pixelEntries, paramsDictionary, propsDictionary) {
    const sourceFileByType = new Map();
    const sourceDefByType = new Map();
    for (const { file, content } of sourceEntries) {
        for (const [key, entry] of Object.entries(content)) {
            const metaType = entry?.meta?.type ?? key;
            sourceFileByType.set(metaType, file);
            sourceDefByType.set(metaType, entry);
        }
    }
    const pixelFilesByType = new Map();
    const pixelObjsByType = new Map();
    for (const { file, content } of pixelEntries) {
        for (const pixelObj of Object.values(content)) {
            for (const metaType of pixelMetaTypes(pixelObj, paramsDictionary)) {
                if (!pixelFilesByType.has(metaType)) pixelFilesByType.set(metaType, new Set());
                pixelFilesByType.get(metaType).add(file);
                if (!pixelObjsByType.has(metaType)) pixelObjsByType.set(metaType, []);
                pixelObjsByType.get(metaType).push(pixelObj);
            }
        }
    }
    return { sourceFileByType, pixelFilesByType, sourceDefByType, pixelObjsByType, paramsDictionary, propsDictionary };
}

const EVENT_PATH_PREFIXES = ['feature.', 'context.', 'journey.'];

function isEventPath(value) {
    return EVENT_PATH_PREFIXES.some((prefix) => value.startsWith(prefix));
}

function isEventPattern(value) {
    const withoutAnchor = value.startsWith('^') ? value.slice(1) : value;
    return EVENT_PATH_PREFIXES.some((prefix) => withoutAnchor.startsWith(prefix.replaceAll('.', '\\.')));
}

// keyPattern fields are rendered as `/<pattern>/` in an issue's identity. Adding
// or removing anchors (^ / $) does not change which source fields a pattern
// matches, so anchored and unanchored forms must share one identity - otherwise
// anchoring a pre-existing (grandfathered) pattern would read as a brand-new
// issue. Plain (non-pattern) selectors are returned unchanged.
function canonicalizeSelector(selector) {
    if (selector.length >= 2 && selector.startsWith('/') && selector.endsWith('/')) {
        const body = selector.slice(1, -1).replace(/^\^/, '').replace(/\$$/, '');
        return `/${body}/`;
    }
    return selector;
}

function sortedValues(values) {
    return [...values].sort((lhs, rhs) => stableStringify(lhs).localeCompare(stableStringify(rhs)));
}

// Keep only validation-affecting attributes. Documentation-only fields such as
// descriptions and examples are deliberately excluded.
function normalizeFieldSchema(schema) {
    const normalized = { type: schema.type || 'string' };
    const enumValues = schema.enum ?? (Object.prototype.hasOwnProperty.call(schema, 'const') ? [schema.const] : undefined);
    if (enumValues) normalized.enum = sortedValues(enumValues);
    for (const key of ['pattern', 'format', 'minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum', 'minLength', 'maxLength']) {
        if (Object.prototype.hasOwnProperty.call(schema, key)) normalized[key] = schema[key];
    }
    return normalized;
}

function flattenSourceFields(value, fieldPath, propsDictionary, fields, resolving = new Set()) {
    if (typeof value === 'string') {
        const shortcut = propsDictionary[value];
        if (!shortcut || resolving.has(value)) {
            fields.set(fieldPath, normalizeFieldSchema({ type: 'string' }));
            return;
        }
        const nextResolving = new Set(resolving);
        nextResolving.add(value);
        flattenSourceFields(shortcut, fieldPath, propsDictionary, fields, nextResolving);
        return;
    }
    if (Array.isArray(value)) {
        fields.set(fieldPath, normalizeFieldSchema({ type: 'string', enum: value }));
        return;
    }
    if (!value || typeof value !== 'object') return;

    if (value.type === 'object') {
        for (const [key, property] of Object.entries(value.properties || {})) {
            flattenSourceFields(property, `${fieldPath}.${key}`, propsDictionary, fields, resolving);
        }
        return;
    }

    const isSchemaLeaf = ['type', 'enum', 'const', 'pattern', 'format', 'minimum', 'maximum'].some((key) =>
        Object.prototype.hasOwnProperty.call(value, key),
    );
    if (isSchemaLeaf) {
        fields.set(fieldPath, normalizeFieldSchema(value));
        return;
    }

    for (const [key, property] of Object.entries(value)) {
        flattenSourceFields(property, fieldPath ? `${fieldPath}.${key}` : key, propsDictionary, fields, resolving);
    }
}

function sourceContract(sourceDef, propsDictionary) {
    const fields = new Map();
    fields.set('feature.name', normalizeFieldSchema({ type: 'string', enum: [sourceDef.feature?.name] }));
    fields.set('feature.status', normalizeFieldSchema({ type: 'string', enum: sourceDef.feature?.status || [] }));
    for (const [key, value] of Object.entries(sourceDef.feature || {})) {
        if (key === 'name' || key === 'status') continue;
        flattenSourceFields(value, `feature.${key}`, propsDictionary, fields);
    }
    for (const section of ['context', 'journey']) {
        if (sourceDef[section]) flattenSourceFields(sourceDef[section], section, propsDictionary, fields);
    }
    return fields;
}

function pixelContract(pixelObjs, paramsDictionary) {
    const fields = [];
    for (const pixelObj of pixelObjs) {
        for (const param of resolvePixelParameters(pixelObj, paramsDictionary)) {
            if (param.key && isEventPath(param.key)) {
                fields.push({ selector: param.key, key: param.key, schema: normalizeFieldSchema(param) });
            } else if (param.keyPattern && isEventPattern(param.keyPattern)) {
                fields.push({ selector: `/${param.keyPattern}/`, keyPattern: param.keyPattern, schema: normalizeFieldSchema(param) });
            }
        }
    }
    return fields;
}

function valuesEqual(lhs, rhs) {
    return stableStringify(lhs) === stableStringify(rhs);
}

// Return why a value accepted by the source schema could be rejected by the
// pixel schema. A broader pixel constraint is compatible with a narrower source.
function incompatibility(sourceSchema, pixelSchema) {
    const compatibleTypes = sourceSchema.type === pixelSchema.type || (sourceSchema.type === 'integer' && pixelSchema.type === 'number');
    if (!compatibleTypes) return `type is ${sourceSchema.type} in the source but ${pixelSchema.type} in the pixel`;

    if (sourceSchema.enum) {
        if (pixelSchema.enum) {
            const rejected = sourceSchema.enum.filter((sourceValue) => !pixelSchema.enum.some((pixelValue) => valuesEqual(sourceValue, pixelValue)));
            if (rejected.length > 0) return `pixel enum does not accept ${rejected.map(stableStringify).join(', ')}`;
        }
    } else if (pixelSchema.enum) {
        return 'pixel has a narrowing enum but the source does not';
    }

    for (const key of ['pattern', 'format']) {
        if (sourceSchema[key] === undefined && pixelSchema[key] !== undefined) return `pixel has a narrowing ${key} but the source does not`;
        if (sourceSchema[key] !== undefined && pixelSchema[key] !== undefined && sourceSchema[key] !== pixelSchema[key]) {
            return `${key} differs between the source and pixel`;
        }
    }

    for (const key of ['minimum', 'exclusiveMinimum', 'minLength']) {
        if (sourceSchema[key] === undefined && pixelSchema[key] !== undefined) return `pixel has a narrowing ${key} but the source does not`;
        if (sourceSchema[key] !== undefined && pixelSchema[key] !== undefined && pixelSchema[key] > sourceSchema[key]) {
            return `pixel ${key} is more restrictive than the source`;
        }
    }
    for (const key of ['maximum', 'exclusiveMaximum', 'maxLength']) {
        if (sourceSchema[key] === undefined && pixelSchema[key] !== undefined) return `pixel has a narrowing ${key} but the source does not`;
        if (sourceSchema[key] !== undefined && pixelSchema[key] !== undefined && pixelSchema[key] < sourceSchema[key]) {
            return `pixel ${key} is more restrictive than the source`;
        }
    }
    return null;
}

function compareContracts(sourceDef, pixelObjs, propsDictionary, paramsDictionary) {
    if (!sourceDef || !pixelObjs?.length) return new Map();

    const sourceFields = sourceContract(sourceDef, propsDictionary);
    const pixelFields = pixelContract(pixelObjs, paramsDictionary);
    const issues = new Map();
    // Key issues by a canonical identity (anchor-insensitive for keyPattern
    // selectors) so anchor-only edits are not mistaken for new issues, while the
    // original fieldPath is kept for display.
    const addIssue = (kind, fieldPath, details) => issues.set(`${kind}|${canonicalizeSelector(fieldPath)}`, { kind, fieldPath, details });

    for (const [fieldPath, sourceSchema] of sourceFields) {
        const applicablePixelFields = pixelFields.filter((field) => {
            if (field.key) return field.key === fieldPath;
            return new RegExp(field.keyPattern).test(fieldPath);
        });
        if (applicablePixelFields.length === 0) {
            addIssue('missing-pixel-field', fieldPath, 'declared by the source but not covered by a pixel key or keyPattern');
            continue;
        }

        const reasons = applicablePixelFields
            .map((field) => incompatibility(sourceSchema, field.schema))
            .filter(Boolean);
        if (reasons.length > 0) addIssue('incompatible-field', fieldPath, [...new Set(reasons)].join('; '));
    }

    for (const pixelField of pixelFields) {
        const represented = pixelField.key
            ? sourceFields.has(pixelField.key)
            : [...sourceFields.keys()].some((fieldPath) => new RegExp(pixelField.keyPattern).test(fieldPath));
        if (!represented) {
            addIssue('missing-source-field', pixelField.selector, 'declared by the pixel but not represented in the source format');
        }
    }

    return issues;
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

// Fast path: this branch touched no pixel/source definitions or dictionaries,
// so there is nothing it could have broken.
if (changed.size === 0) {
    console.log('Wide-event consistency check passed.');
    process.exit(0);
}

const current = buildSnapshot(
    readJson5Files(WIDE_EVENTS_DIR),
    readJson5Files(PIXELS_DIR),
    readJson5File(PIXEL_PARAMS_FILE),
    readJson5File(WIDE_EVENT_PROPS_FILE),
);
const baseIdx = buildSnapshot(
    readJson5FilesAtRef(base, repoRel(WIDE_EVENTS_DIR)),
    readJson5FilesAtRef(base, repoRel(PIXELS_DIR)),
    readJson5FileAtRef(base, repoRel(PIXEL_PARAMS_FILE)),
    readJson5FileAtRef(base, repoRel(WIDE_EVENT_PROPS_FILE)),
);

const currentIncomplete = incompleteTypes(current);
const baseIncomplete = incompleteTypes(baseIdx);
const currentComplete = completeTypes(current);

const completenessErrors = [];
const formatErrors = [];

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

// Rule 2 - format consistency: compare normalized event payload contracts. Main
// may already contain legitimate quirks, so only fail for an issue kind + field
// path that was not present at the merge-base. Fixing an old issue is allowed.
for (const metaType of currentComplete) {
    const currentIssues = compareContracts(
        current.sourceDefByType.get(metaType),
        current.pixelObjsByType.get(metaType),
        current.propsDictionary,
        current.paramsDictionary,
    );
    const baseIssues = compareContracts(
        baseIdx.sourceDefByType.get(metaType),
        baseIdx.pixelObjsByType.get(metaType),
        baseIdx.propsDictionary,
        baseIdx.paramsDictionary,
    );
    for (const [issueId, issue] of currentIssues) {
        if (baseIssues.has(issueId)) continue;
        formatErrors.push({
            metaType,
            ...issue,
            sourceFile: current.sourceFileByType.get(metaType),
            pixelFiles: [...current.pixelFilesByType.get(metaType)].join(', '),
        });
    }
}

if (completenessErrors.length === 0 && formatErrors.length === 0) {
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

if (formatErrors.length > 0) {
    lines.push('');
    lines.push('-- Wide-event format mismatch ----------------------------------------------');
    lines.push('This branch introduced event payload fields or constraints that are not represented');
    lines.push('compatibly by both definitions. Pixel-only transport/documentation parameters are ignored,');
    lines.push('and pre-existing field-level inconsistencies are grandfathered:');
    lines.push('');
    for (const e of formatErrors) {
        lines.push(`  • meta.type "${e.metaType}" - ${e.kind} at "${e.fieldPath}"`);
        lines.push(`      ${e.details}`);
        lines.push(`      source definition: ${e.sourceFile}`);
        lines.push(`      pixel definition:  ${e.pixelFiles}`);
        lines.push('');
    }
    lines.push('Fix the event-specific field in the source or pixel definition. If the source schema shape');
    lines.push('changed, also bump its `meta.version`; the separate immutability check enforces that rule.');
}

console.error(lines.join('\n'));
process.exit(1);
