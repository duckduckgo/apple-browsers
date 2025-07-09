import { platformSupport } from '../../src/features.js';
import { readFileSync } from 'fs';
import { cwd } from '../../../scripts/script-utils.js';
import { join } from 'path';
import * as esbuild from 'esbuild';
import { commentPlugin } from './comment-plugin.js';
const ROOT = join(cwd(import.meta.url), '..', '..');
const DEBUG = false;

const prefixMessage = '/*! © DuckDuckGo ContentScopeScripts protections https://github.com/duckduckgo/content-scope-scripts/ */';

/**
 * @param {object} params
 * @param {string} params.scriptPath
 * @param {string} params.platform
 * @param {string[]} [params.featureNames]
 * @param {string} [params.name]
 * @return {Promise<string>}
 */
export async function bundle(params) {
    const { scriptPath, platform, name, featureNames } = params;

    const extensions = ['firefox', 'chrome-mv3'];
    const isExtension = extensions.includes(platform);
    let trackerLookup = '$TRACKER_LOOKUP$';
    if (!isExtension) {
        const trackerLookupData = readFileSync('../build/tracker-lookup.json', 'utf8');
        trackerLookup = trackerLookupData;
    }
    const loadFeaturesPlugin = loadFeatures(platform, featureNames);
    // The code is using a global, that we define here which means once tree shaken we get a browser specific output.

    /** @type {import("esbuild").BuildOptions} */
    const buildOptions = {
        entryPoints: [scriptPath],
        write: false,
        outdir: 'build',
        target: 'es2021',
        format: 'iife',
        bundle: true,
        metafile: true,
        legalComments: 'inline',
        globalName: name,
        loader: {
            '.css': 'text',
            '.svg': 'text',
        },
        define: {
            'import.meta.env': 'development',
            'import.meta.injectName': JSON.stringify(platform),
            'import.meta.trackerLookup': trackerLookup,
        },
        plugins: [loadFeaturesPlugin, commentPlugin()],
        banner: {
            js: prefixMessage,
        },
    };

    const result = await esbuild.build(buildOptions);

    if (result.metafile && DEBUG) {
        console.log(await esbuild.analyzeMetafile(result.metafile));
    }

    if (result.errors.length === 0 && result.outputFiles) {
        return result.outputFiles[0].text || '';
    } else {
        console.log(result.errors);
        console.log(result.warnings);
        throw new Error('could not continue');
    }
}

/**
 * Include the features required on each platform
 *
 * @param {string} platform
 * @param {string[]} featureNames
 * @returns {import("esbuild").Plugin}
 */
function loadFeatures(platform, featureNames = platformSupport[platform]) {
    const pluginId = 'ddg:platformFeatures';
    return {
        name: 'ddg:platformFeatures',
        setup(build) {
            build.onResolve({ filter: new RegExp(pluginId) }, (args) => {
                return {
                    path: args.path,
                    namespace: pluginId,
                };
            });
            build.onLoad({ filter: /.*/, namespace: pluginId }, () => {
                // convert a list of feature names to
                const imports = featureNames.map((featureName) => {
                    const fileName = getFileName(featureName);
                    const path = `./src/features/${fileName}.js`;
                    const ident = `ddg_feature_${featureName}`;
                    return {
                        ident,
                        importPath: path,
                    };
                });

                const importString = imports.map((imp) => `import ${imp.ident} from ${JSON.stringify(imp.importPath)}`).join(';\n');

                const exportsString = imports.map((imp) => `${imp.ident}`).join(',\n    ');

                const exportString = `export default {\n    ${exportsString}\n}`;

                return {
                    loader: 'js',
                    resolveDir: ROOT,
                    contents: [importString, exportString].join('\n'),
                };
            });
        },
    };
}

/**
 * Convert `featureName` to `feature-name`
 *
 * @param {string} featureName
 * @return {string}
 */
function getFileName(featureName) {
    return featureName.replace(/([a-zA-Z])(?=[A-Z0-9])/g, '$1-').toLowerCase();
}
