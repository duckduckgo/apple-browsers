import { platformSupport } from '../src/features.js';
import path from 'path';
import { fileURLToPath } from 'url';
import { readFile } from 'fs/promises';
import * as glob from 'glob';
import { formatErrors } from '@duckduckgo/privacy-configuration/tests/schema-validation.js';
import ApiManipulation from '../src/features/api-manipulation.js';

// TODO: Ignore eslint redeclare as we're linting for esm and cjs
// eslint-disable-next-line no-redeclare
const __filename = fileURLToPath(import.meta.url);
// eslint-disable-next-line no-redeclare
const __dirname = path.dirname(__filename);

describe('Features definition', () => {
    it('calls `webCompat` before `fingerPrintingScreenSize` https://app.asana.com/0/1177771139624306/1204944717262422/f', () => {
        // ensuring this order doesn't change, as it recently caused breakage
        expect(platformSupport.apple).toEqual([
            'webCompat',
            'duckPlayerNative',
            'scriptlets',
            'fingerprintingAudio',
            'fingerprintingBattery',
            'fingerprintingCanvas',
            'googleRejected',
            'gpc',
            'fingerprintingHardware',
            'referrer',
            'fingerprintingScreenSize',
            'fingerprintingTemporaryStorage',
            'navigatorInterface',
            'elementHiding',
            'exceptionHandler',
            'apiManipulation',
        ]);
    });
});

describe('test-pages/*/config/*.json schema validation', () => {
    let Ajv, schemaGenerator;
    beforeAll(async () => {
        Ajv = (await import('ajv')).default;
        schemaGenerator = await import('ts-json-schema-generator');
    });

    // TODO make the config export all of this so it can be imported
    function createGenerator() {
        return schemaGenerator.createGenerator({
            path: path.resolve(__dirname, '../../node_modules/@duckduckgo/privacy-configuration/schema/config.ts'),
        });
    }

    function getSchema(schemaName) {
        return createGenerator().createSchema(schemaName);
    }

    function createValidator(schemaName) {
        const ajv = new Ajv({ allowUnionTypes: true });
        return ajv.compile(getSchema(schemaName));
    }

    // Utility to ensure 'hash' exists on all features in the config
    // Ideally we would not have these required in the config, it's pretty unnecessary for tests.
    function ensureHashOnFeatures(config) {
        if (config && typeof config === 'object' && config.features) {
            for (const featureKey of Object.keys(config.features)) {
                if (config.features[featureKey] && typeof config.features[featureKey] === 'object') {
                    if (!('hash' in config.features[featureKey])) {
                        config.features[featureKey].hash = '';
                    }
                }
            }
        }
        return config;
    }

    const configFiles = glob
        .sync('../integration-test/test-pages/*/config/*.json', { cwd: __dirname })
        .map((p) => path.resolve(__dirname, p));

    // Legacy allowlist: skip schema validation for these known legacy files
    // Some of these have expected invalid configs
    const legacyAllowlist = [
        // Favicon configs
        path.resolve(__dirname, '../integration-test/test-pages/favicon/config/favicon-disabled.json'),
        path.resolve(__dirname, '../integration-test/test-pages/favicon/config/favicon-absent.json'),
        path.resolve(__dirname, '../integration-test/test-pages/favicon/config/favicon-enabled.json'),
        path.resolve(__dirname, '../integration-test/test-pages/favicon/config/favicon-monitor-disabled.json'),
        // Duckplayer configs
        path.resolve(__dirname, '../integration-test/test-pages/duckplayer/config/overlays-live.json'),
        path.resolve(__dirname, '../integration-test/test-pages/duckplayer/config/click-interceptions-disabled.json'),
        path.resolve(__dirname, '../integration-test/test-pages/duckplayer/config/disabled.json'),
        path.resolve(__dirname, '../integration-test/test-pages/duckplayer/config/overlays-drawer.json'),
        path.resolve(__dirname, '../integration-test/test-pages/duckplayer/config/overlays.json'),
        path.resolve(__dirname, '../integration-test/test-pages/duckplayer/config/thumbnail-overlays-disabled.json'),
        path.resolve(__dirname, '../integration-test/test-pages/duckplayer/config/video-alt-selectors.json'),
        path.resolve(__dirname, '../integration-test/test-pages/duckplayer/config/video-overlays-disabled.json'),
        // Message bridge configs
        path.resolve(__dirname, '../integration-test/test-pages/message-bridge/config/message-bridge-enabled.json'),
        path.resolve(__dirname, '../integration-test/test-pages/message-bridge/config/message-bridge-disabled.json'),
    ];
    for (const configPath of configFiles) {
        if (legacyAllowlist.includes(configPath)) {
            xit(`LEGACY: skipped schema validation for ${path.relative(process.cwd(), configPath)}`, () => {});
            continue;
        }
        it(`should match the CurrentGenericConfig schema: ${path.relative(process.cwd(), configPath)}`, async () => {
            let config = JSON.parse(await readFile(configPath, 'utf-8'));
            config = ensureHashOnFeatures(config);
            const validate = createValidator('CurrentGenericConfig');
            const valid = validate(config);
            if (!valid) {
                throw new Error(`Schema validation failed for ${configPath}: ` + formatErrors(validate.errors));
            }
        });
    }
});

describe('ApiManipulation', () => {
    let apiManipulation;
    let dummyTarget;

    beforeEach(() => {
        apiManipulation = new ApiManipulation(
            'apiManipulation',
            {},
            {
                bundledConfig: { features: { apiManipulation: { state: 'enabled', exceptions: [] } } },
                site: { domain: 'test.com' },
                platform: { version: '1.0.0' },
            },
        );
        dummyTarget = {};
    });

    it('defines a new property if define: true is set and property does not exist', () => {
        const change = {
            type: 'descriptor',
            getterValue: { type: 'string', value: 'defined!' },
            define: true,
        };
        apiManipulation.wrapApiDescriptor(dummyTarget, 'definedByConfig', change);
        expect(dummyTarget.definedByConfig).toBe('defined!');
    });

    it('does not define a property if define is not set and property does not exist', () => {
        const change = {
            type: 'descriptor',
            getterValue: { type: 'string', value: 'should not exist' },
        };
        apiManipulation.wrapApiDescriptor(dummyTarget, 'notDefinedByConfig', change);
        expect(dummyTarget.notDefinedByConfig).toBeUndefined();
    });

    it('wraps an existing property if present', () => {
        Object.defineProperty(dummyTarget, 'hardwareConcurrency', {
            get: () => 4,
            configurable: true,
            enumerable: true,
        });
        const change = {
            type: 'descriptor',
            getterValue: { type: 'number', value: 222 },
        };
        apiManipulation.wrapApiDescriptor(dummyTarget, 'hardwareConcurrency', change);
        // The getter should now return 222
        expect(dummyTarget.hardwareConcurrency).toBe(222);
    });
});
