import { isLaunchFile } from '../scripts/script-utils.js';
import { readdir } from 'fs/promises';
import { join, basename } from 'node:path';
import { readFileSync, writeFileSync } from 'node:fs';

const paths = [join('pages', 'new-tab'), join('pages', 'history')];
const base = {
    smartling: {
        string_format: 'icu',
        translate_paths: [
            {
                path: '*/title',
                key: '{*}/title',
                instruction: '*/note',
            },
        ],
    },
};

if (isLaunchFile(import.meta.url)) {
    for (const path of paths) {
        await processPage(path);
    }
}

/**
 * @param {string} path
 */
async function processPage(path) {
    const targetName = basename(path);
    const outputFile = join(path, '/public/locales/en', `${targetName}.json`);
    const dirents = await readdir(path, { withFileTypes: true, recursive: true });
    const rawEntries = dirents
        .filter((entry) => entry.isFile() && entry.name === 'strings.json')
        .map((entry) => {
            const path = join(entry.parentPath, entry.name);
            const raw = readFileSync(path, 'utf8');
            let json;
            try {
                json = JSON.parse(raw);
            } catch (e) {
                throw new Error(`${e.name} in '${path}' ${e.name}\n  ${e.message}`);
            }
            return {
                path,
                raw,
                json,
            };
        });

    for (const rawEntry of rawEntries) {
        console.log(`✅ adding ${rawEntry.path} to ${targetName}.json`);
    }

    const entries = rawEntries.map((entry) => Object.entries(entry.json)).flat();
    const object = Object.fromEntries(entries);
    const withBase = { ...base, ...object };
    const string = JSON.stringify(withBase, null, 2);
    writeFileSync(outputFile, string);
}
