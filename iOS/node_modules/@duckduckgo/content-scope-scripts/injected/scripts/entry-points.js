import { bundle } from './utils/build.js';
import { parseArgs, write } from '../../scripts/script-utils.js';

/**
 * @typedef Build
 * @property {string} input
 * @property {string[]} output
 *
 * @typedef {Record<NonNullable<ImportMeta['injectName']>, Build>} BuildManifest
 */

/** @satisfies {BuildManifest} */
const builds = {
    firefox: {
        input: 'entry-points/extension-mv3.js',
        output: ['../build/firefox/inject.js'],
    },
    apple: {
        input: 'entry-points/apple.js',
        output: ['../Sources/ContentScopeScripts/dist/contentScope.js'],
    },
    'apple-isolated': {
        input: 'entry-points/apple.js',
        output: ['../Sources/ContentScopeScripts/dist/contentScopeIsolated.js'],
    },
    android: {
        input: 'entry-points/android.js',
        output: ['../build/android/contentScope.js'],
    },
    'android-broker-protection': {
        input: 'entry-points/android.js',
        output: ['../build/android/brokerProtection.js'],
    },
    'android-autofill-password-import': {
        input: 'entry-points/android.js',
        output: ['../build/android/autofillPasswordImport.js'],
    },
    windows: {
        input: 'entry-points/windows.js',
        output: ['../build/windows/contentScope.js'],
    },
    integration: {
        input: 'entry-points/integration.js',
        output: [
            '../build/integration/contentScope.js',
            'integration-test/extension/contentScope.js',
            'integration-test/test-pages/build/contentScope.js',
        ],
    },
    'chrome-mv3': {
        input: 'entry-points/extension-mv3.js',
        output: ['../build/chrome-mv3/inject.js'],
    },
};

async function init() {
    // verify the input
    const requiredFields = [];
    const args = parseArgs(process.argv.slice(2), requiredFields);

    // if a platform was given as an argument, just build that platform
    if (args.platform) {
        const build = builds[args.platform];
        if (!build) {
            throw new Error('unsupported platform: ' + args.platform);
        }
        const output = await bundle({ scriptPath: build.input, platform: args.platform });

        // bundle and write the output
        write([build.output], output);

        return;
    }

    // otherwise, just build them all
    for (const [injectName, build] of Object.entries(builds)) {
        const output = await bundle({ scriptPath: build.input, platform: injectName });
        write(build.output, output);
        console.log('✅', injectName, build.output[0]);
    }
}

init();
