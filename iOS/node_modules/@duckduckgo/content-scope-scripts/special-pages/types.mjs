/* eslint-disable promise/prefer-await-to-then */
import { join } from 'node:path';
import { existsSync, readdirSync } from 'node:fs';
import { cwd, isLaunchFile } from '../scripts/script-utils.js';
import { buildTypes } from '../types-generator/build-types.mjs';

const specialPagesRoot = cwd(import.meta.url);
const pageList = readdirSync(join(specialPagesRoot, 'pages'), { withFileTypes: true })
    .filter((x) => x.isDirectory())
    .map((x) => x.name);

/** @type {Record<string, import('../types-generator/build-types.mjs').Mapping>} */
const specialPagesTypes = {};
for (const pageListElement of pageList) {
    const input = join(specialPagesRoot, 'pages', pageListElement, 'messages');
    const output = join(specialPagesRoot, 'pages', pageListElement, 'types');
    if (!existsSync(input)) {
        console.warn(`No messages directory found for ${pageListElement}`);
        continue;
    }
    specialPagesTypes[pageListElement] = {
        schemaDir: input,
        typesDir: output,
        exclude: process.platform === 'win32',
        kind: 'single',
        resolve: (_dirname) => '../src/index.js',
        className: (topLevelType) => topLevelType.replace('Messages', 'Page'),
        filename: `${pageListElement}.ts`,
    };
}

if (isLaunchFile(import.meta.url)) {
    buildTypes(specialPagesTypes).catch((error) => {
        console.error(error);
        process.exit(1);
    });
}
