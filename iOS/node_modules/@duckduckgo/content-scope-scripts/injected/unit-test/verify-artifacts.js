import { join, relative } from 'node:path';
import { readFileSync, statSync } from 'node:fs';
import { cwd } from '../../scripts/script-utils.js';

// path helpers
const ROOT = join(cwd(import.meta.url), '..', '..');
console.log(ROOT);
const BUILD = join(ROOT, 'build');
const APPLE_BUILD = join(ROOT, 'Sources/ContentScopeScripts/dist');
console.log(APPLE_BUILD);
let CSS_OUTPUT_SIZE = 770_000;
if (process.platform === 'win32') {
    CSS_OUTPUT_SIZE = CSS_OUTPUT_SIZE * 1.1; // 10% larger for Windows due to line endings
}

const checks = {
    android: {
        file: join(BUILD, 'android/contentScope.js'),
        tests: [{ kind: 'maxFileSize', value: CSS_OUTPUT_SIZE }],
    },
    'chrome-mv3': {
        file: join(BUILD, 'chrome-mv3/inject.js'),
        tests: [
            { kind: 'maxFileSize', value: CSS_OUTPUT_SIZE },
            { kind: 'containsString', text: '$TRACKER_LOOKUP$', includes: true },
            { kind: 'containsString', text: 'Copyright (C) 2010 by Johannes Baagøe <baagoe@baagoe.org>', includes: true },
            { kind: 'containsString', text: 'Copyright 2019 David Bau.', includes: true },
        ],
    },
    firefox: {
        file: join(BUILD, 'firefox/inject.js'),
        tests: [
            { kind: 'maxFileSize', value: CSS_OUTPUT_SIZE },
            { kind: 'containsString', text: '$TRACKER_LOOKUP$', includes: true },
        ],
    },
    integration: {
        file: join(BUILD, 'integration/contentScope.js'),
        tests: [{ kind: 'containsString', text: 'init_define_import_meta_trackerLookup = ', includes: true }],
    },
    windows: {
        file: join(BUILD, 'windows/contentScope.js'),
        tests: [{ kind: 'maxFileSize', value: CSS_OUTPUT_SIZE }],
    },
    apple: {
        file: join(APPLE_BUILD, 'contentScope.js'),
        tests: [
            { kind: 'maxFileSize', value: CSS_OUTPUT_SIZE },
            { kind: 'containsString', text: '#bundledConfig', includes: false },
        ],
    },
    'apple-isolated': {
        file: join(APPLE_BUILD, 'contentScopeIsolated.js'),
        tests: [
            { kind: 'maxFileSize', value: CSS_OUTPUT_SIZE },
            { kind: 'containsString', text: 'Copyright (c) 2014-2015, hassansin', includes: true },
        ],
    },
};

describe('checks', () => {
    for (const [platformName, platformChecks] of Object.entries(checks)) {
        for (const check of platformChecks.tests) {
            const localPath = relative(ROOT, platformChecks.file);
            if (check.kind === 'maxFileSize') {
                it(`${platformName}: '${localPath}' is smaller than ${check.value}`, () => {
                    const stats = statSync(platformChecks.file);
                    expect(stats.size).toBeLessThan(check.value);
                });
            }
            if (check.kind === 'containsString') {
                it(`${platformName}: '${localPath}' contains ${check.text}`, () => {
                    const fileContents = readFileSync(platformChecks.file).toString();
                    const includes = fileContents.includes(check.text);
                    if (check.includes) {
                        expect(includes).toBeTrue();
                    } else {
                        expect(includes).toBeFalse();
                    }
                });
            }
        }
    }
});
