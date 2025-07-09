import {
    matchHostname,
    postDebugMessage,
    initStringExemptionLists,
    processConfig,
    satisfiesMinVersion,
    getTabHostname,
} from '../src/utils.js';
import { polyfillProcessGlobals } from './helpers/polyfill-process-globals.js';

polyfillProcessGlobals();

describe('Helpers checks', () => {
    describe('matchHostname', () => {
        it('Expect results on matchHostnames', () => {
            expect(matchHostname('b.domain.com', 'domain.com')).toBeTrue();
            expect(matchHostname('domain.com', 'b.domain.com')).toBeFalse();
            expect(matchHostname('domain.com', 'domain.com')).toBeTrue();
            expect(matchHostname('a.b.c.e.f.domain.com', 'domain.com')).toBeTrue();
            expect(matchHostname('otherdomain.com', 'domain.com')).toBeFalse();
            expect(matchHostname('domain.com', 'otherdomain.com')).toBeFalse();
        });
    });

    it('processes config in expected way for minSupportedVersion and numeric versions', () => {
        const configIn = {
            features: {
                testFeature: {
                    state: 'enabled',
                    settings: {
                        beep: 'boop',
                    },
                    exceptions: [],
                },
                testFeatureTooBig: {
                    state: 'enabled',
                    minSupportedVersion: 100,
                    settings: {},
                    exceptions: [],
                },
                testFeatureSmall: {
                    state: 'enabled',
                    minSupportedVersion: 99,
                    settings: {},
                    exceptions: [],
                },
                testFeatureSmaller: {
                    state: 'enabled',
                    minSupportedVersion: 98,
                    settings: {
                        barp: true,
                    },
                    exceptions: [],
                },
                testFeatureOutlier: {
                    state: 'enabled',
                    minSupportedVersion: 97000,
                    settings: {},
                    exceptions: [],
                },
            },
            unprotectedTemporary: [],
        };
        const processedConfig = processConfig(
            configIn,
            [],
            {
                platform: {
                    name: 'android',
                },
                versionNumber: 99,
                sessionKey: 'testSessionKey',
            },
            [],
        );
        expect(processedConfig).toEqual({
            site: {
                domain: 'localhost',
                url: 'http://localhost:8080/',
                isBroken: false,
                allowlisted: false,
                // testFeatureTooBig is not enabled because it's minSupportedVersion is 100
                enabledFeatures: ['testFeature', 'testFeatureSmall', 'testFeatureSmaller'],
            },
            featureSettings: {
                testFeature: {
                    beep: 'boop',
                },
                testFeatureSmall: {},
                testFeatureSmaller: {
                    barp: true,
                },
            },
            platform: {
                name: 'android',
                version: 99,
            },
            versionNumber: 99,
            sessionKey: 'testSessionKey',
            bundledConfig: configIn,
        });
    });

    it('processes config in expected way for minSupportedVersion and string versions', () => {
        const configIn = {
            features: {
                testFeature: {
                    state: 'enabled',
                    settings: {
                        beep: 'boop',
                    },
                    exceptions: [],
                },
                testFeatureTooBig: {
                    state: 'enabled',
                    minSupportedVersion: '1.0.0',
                    settings: {},
                    exceptions: [],
                },
                testFeatureSmall: {
                    state: 'enabled',
                    minSupportedVersion: '0.9.9',
                    settings: {},
                    exceptions: [],
                },
                testFeatureSmaller: {
                    state: 'enabled',
                    minSupportedVersion: '0.9.8',
                    settings: {
                        barp: true,
                    },
                    exceptions: [],
                },
                testFeatureOutlier: {
                    state: 'enabled',
                    minSupportedVersion: '97.0.00',
                    settings: {},
                    exceptions: [],
                },
            },
            unprotectedTemporary: [],
        };
        const processedConfig = processConfig(
            configIn,
            [],
            {
                platform: {
                    name: 'ios',
                },
                versionString: '0.9.9',
                sessionKey: 'testSessionKey',
            },
            [],
        );
        expect(processedConfig).toEqual({
            site: {
                domain: 'localhost',
                url: 'http://localhost:8080/',
                isBroken: false,
                allowlisted: false,
                // testFeatureTooBig is not enabled because it's minSupportedVersion is 100
                enabledFeatures: ['testFeature', 'testFeatureSmall', 'testFeatureSmaller'],
            },
            featureSettings: {
                testFeature: {
                    beep: 'boop',
                },
                testFeatureSmall: {},
                testFeatureSmaller: {
                    barp: true,
                },
            },
            platform: {
                name: 'ios',
                version: '0.9.9',
            },
            versionString: '0.9.9',
            sessionKey: 'testSessionKey',
            bundledConfig: configIn,
        });
    });

    it('does not enable features with state "preview"', () => {
        const configIn = {
            features: {
                testFeature: {
                    state: 'enabled',
                    settings: {},
                    exceptions: [],
                },
                previewFeature: {
                    state: 'preview',
                    settings: {},
                    exceptions: [],
                },
            },
            unprotectedTemporary: [],
        };
        const processedConfig = processConfig(
            configIn,
            [],
            {
                platform: {
                    name: 'android',
                },
                versionNumber: 99,
                sessionKey: 'testSessionKey',
            },
            [],
        );
        expect(processedConfig.site.enabledFeatures).toEqual(['testFeature']);
        expect(processedConfig.featureSettings).toEqual({ testFeature: {} });
    });

    describe('utils.satisfiesMinVersion', () => {
        // Min version, Extension version, outcome
        /** @type {[string, string, boolean][]} */
        const cases = [
            ['12', '12', true],
            ['12', '13', true],
            ['12.1', '12.1', true],
            ['12.1.1', '12.1.1', true],
            ['12.1.1', '12.1.2', true],
            ['12.1.1', '12.2.0', true],
            ['13.12.12', '12.12.12', false],
            ['12.13.12', '12.12.12', false],
            ['12.12.13', '12.12.12', false],
            ['102.12.12', '102.12.11', false],
            ['102.12.12', '102.12.12', true],
            ['102.12.12', '102.12.13', true],
            ['102.12.12.1', '101', false],
            ['102.12.12.1', '103', true],
            ['102.12.12.1', '104', true],
            ['103', '102.12.12.1', false],
            ['101', '102.12.12.1', true],
            ['102.12.12.1', '102.13.12', true],
            ['102.12.12.1', '102.12.12', false],
            ['102.12.12.2', '102.12.12.1', false],
            ['102.12.12.1', '102.12.12.2', true],
            ['102.12.12.1', '102.12.12.1', true],
            ['102.12.12.1', '102.12.12.3', true],
            ['102.12.12.1', '102.12.12.1.1', true],
            ['102.12.12.1', '102.12.12.2.1', true],
            ['102.12.12.1', '102.12.12.1.1.1.1.1.1.1', true],
        ];
        for (const testCase of cases) {
            const [versionString, extensionVersionString, expectedOutcome] = testCase;
            it(`returns ${JSON.stringify(expectedOutcome)} for ${versionString} compared to ${extensionVersionString}`, () => {
                expect(satisfiesMinVersion(versionString, extensionVersionString)).toEqual(expectedOutcome);
            });
        }
    });

    describe('utils.postDebugMessage', () => {
        const counters = new Map();
        globalThis.postMessage = (message) => {
            counters.set(message.action, (counters.get(message.action) || 0) + 1);
        };
        initStringExemptionLists({ debug: false });
        for (let i = 0; i < 10; i++) {
            postDebugMessage('testa', { ding: 1 });
            postDebugMessage('testa', { ding: 2 });
            postDebugMessage('testb', { boop: true });
            postDebugMessage('testc', { boop: true }, true);
        }
        it('does not trigger post messages without debug flag', () => {
            expect(counters.get('testa')).toEqual(undefined);
            expect(counters.get('testb')).toEqual(undefined);
            expect(counters.get('testc')).toEqual(10);
        });

        initStringExemptionLists({ debug: true });
        for (let i = 0; i < 6000; i++) {
            postDebugMessage('testd', { ding: 1 });
            postDebugMessage('testd', { ding: 2 });
            postDebugMessage('teste', { boop: true });
            postDebugMessage('testf', { boop: true }, true);
        }
        it('posts messages', () => {
            expect(counters.get('testd')).toEqual(5000);
            expect(counters.get('teste')).toEqual(5000);
            expect(counters.get('testf')).toEqual(5000);
        });
    });

    describe('utils.getTabHostname', () => {
        it('returns the hostname of the URL', () => {
            const hostname = getTabHostname();
            expect(hostname).toEqual('localhost');

            const reset = polyfillProcessGlobals('http://example.com');
            const hostname2 = getTabHostname();
            expect(hostname2).toEqual('example.com');
            reset();

            const hostname3 = getTabHostname();
            expect(hostname3).toEqual('localhost');

            // Validates when we're in a frame thats sandboxed so top is null
            const reset2 = polyfillProcessGlobals('https://bloop.com', ['http://example.com'], true);
            const hostname5 = getTabHostname();
            expect(hostname5).toEqual('example.com');
            reset2();
        });
    });
});
