import { readdirSync, readFileSync } from 'fs';
import { join } from 'path';
import { write } from '../../scripts/script-utils.js';

/**
 * This script loads the current JSON-based locales files and merges them into
 * a single importable ES module for bundling purposes
 * @param localesRoot
 * @return {string}
 */
function bundle(localesRoot) {
    const locales = {};
    const localeDirs = readdirSync(localesRoot).filter((f) => !f.startsWith('.'));
    for (const locale of localeDirs) {
        locales[locale] = {};
        const dir = join(localesRoot, locale);
        const files = readdirSync(dir);
        for (const file of files) {
            const localeJSON = readFileSync(join(dir, file));
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            const stringObj = JSON.parse(localeJSON);
            locales[locale][file] = {};
            for (const [key, value] of Object.entries(stringObj)) {
                if (key !== 'smartling') {
                    locales[locale][file][key] = value.title;
                }
            }
        }
    }

    return 'export default `' + JSON.stringify(locales).replace('`', '\\`') + '`';
}

const jobs = {
    'src/locales/click-to-load': '../build/locales/ctl-locales.js',
    'src/locales/duckplayer': '../build/locales/duckplayer-locales.js',
};

for (const [dir, output] of Object.entries(jobs)) {
    const bundled = bundle(dir);
    write([output], bundled);
}
