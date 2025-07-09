import { cwd, isLaunchFile } from '../../scripts/script-utils.js';
import { join } from 'node:path';
import { buildTypes } from '../../types-generator/build-types.mjs';

const injectRoot = join(cwd(import.meta.url), '..');

/** @type {Record<string, import('../../types-generator/build-types.mjs').Mapping>} */
const injectSchemaMapping = {
    /**
     * Add more mappings here
     *  - `schema` should be an absolute path to a valid JSON Schema document
     *  - `types` should be an absolute path to the output file
     */
    'Schema Messages': {
        schemaDir: join(injectRoot, 'src/messages'),
        typesDir: join(injectRoot, 'src/types'),
        // todo: fix this on windows.
        exclude: process.platform === 'win32',
        kind: 'messages',
        resolve: (dirname) => '../features/' + dirname + '.js',
        className: (topLevelType) => topLevelType.replace('Messages', ''),
    },
};

if (isLaunchFile(import.meta.url)) {
    buildTypes(injectSchemaMapping)
        // eslint-disable-next-line promise/prefer-await-to-then
        .catch((error) => {
            console.error(error);
            process.exit(1);
        });
}
