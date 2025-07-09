import ContentFeature from '../src/content-feature.js';

describe('ContentFeature class', () => {
    it('Should trigger getFeatureSettingEnabled for the correct domain', () => {
        let didRun = false;
        class MyTestFeature extends ContentFeature {
            init() {
                expect(this.getFeatureSetting('test')).toBe('enabled3');
                expect(this.getFeatureSetting('otherTest')).toBe('enabled');
                expect(this.getFeatureSetting('otherOtherTest')).toBe('ding');
                expect(this.getFeatureSetting('arrayTest')).toBe('enabledArray');
                // Following key doesn't exist so it should return false
                expect(this.getFeatureSettingEnabled('someNonExistantKey')).toBe(false);
                expect(this.getFeatureSettingEnabled('disabledStatus')).toBe(false);
                expect(this.getFeatureSettingEnabled('internalStatus')).toBe(false);
                expect(this.getFeatureSettingEnabled('enabledStatus')).toBe(true);
                expect(this.getFeatureSettingEnabled('overridenStatus')).toBe(false);
                expect(this.getFeatureSettingEnabled('disabledOverridenStatus')).toBe(true);
                expect(this.getFeatureSettingEnabled('statusObject')).toBe(true);
                expect(this.getFeatureSettingEnabled('statusDisabledObject')).toBe(false);
                didRun = true;
            }
        }

        const args = {
            site: {
                domain: 'beep.example.com',
                url: 'http://beep.example.com',
            },
            featureSettings: {
                test: {
                    test: 'enabled',
                    otherTest: 'disabled',
                    otherOtherTest: 'ding',
                    arrayTest: 'enabled',
                    disabledStatus: 'disabled',
                    internalStatus: 'internal', // not currently supported
                    enabledStatus: 'enabled',
                    overridenStatus: 'enabled',
                    disabledOverridenStatus: 'disabled',
                    statusObject: {
                        state: 'enabled',
                        bloop: true,
                    },
                    statusDisabledObject: {
                        state: 'disabled',
                        bloop2: true,
                    },
                    domains: [
                        {
                            domain: 'example.com',
                            patchSettings: [
                                { op: 'replace', path: '/test', value: 'enabled2' },
                                { op: 'replace', path: '/otherTest', value: 'enabled' },
                                { op: 'replace', path: '/overridenStatus', value: 'disabled' },
                                { op: 'replace', path: '/disabledOverridenStatus', value: 'enabled' },
                            ],
                        },
                        {
                            domain: 'beep.example.com',
                            patchSettings: [{ op: 'replace', path: '/test', value: 'enabled3' }],
                        },
                        {
                            domain: ['meep.com', 'example.com'],
                            patchSettings: [{ op: 'replace', path: '/arrayTest', value: 'enabledArray' }],
                        },
                    ],
                },
            },
        };
        const me = new MyTestFeature('test', {}, args);
        me.callInit(args);
        expect(didRun).withContext('Should run').toBeTrue();
    });

    it('Should trigger getFeatureSettingEnabled for the correct domain', () => {
        let didRun = false;
        class MyTestFeature2 extends ContentFeature {
            init() {
                expect(this.getFeatureSetting('test')).toBe('enabled3');
                expect(this.getFeatureSetting('otherTest')).toBe('enabled');
                expect(this.getFeatureSetting('otherOtherTest')).toBe('ding');
                expect(this.getFeatureSetting('arrayTest')).toBe('enabledArray');
                expect(this.getFeatureSetting('pathTest')).toBe('beep');
                expect(this.getFeatureSetting('pathTestNotApply')).toBe('nope');
                expect(this.getFeatureSetting('pathTestShort')).toBe('beep');
                expect(this.getFeatureSetting('pathTestAsterix')).toBe('comic');
                expect(this.getFeatureSetting('pathTestPlaceholder')).toBe('place');
                expect(this.getFeatureSetting('domainWildcard')).toBe('wildwest');
                expect(this.getFeatureSetting('domainWildcardNope')).toBe('nope');
                expect(this.getFeatureSetting('invalidCheck')).toBe('nope');
                didRun = true;
            }
        }

        const args = {
            site: {
                domain: 'beep.example.com',
                url: 'http://beep.example.com/path/path/me',
            },
            featureSettings: {
                test: {
                    test: 'enabled',
                    otherTest: 'disabled',
                    otherOtherTest: 'ding',
                    arrayTest: 'enabled',
                    pathTest: 'nope',
                    pathTestNotApply: 'nope',
                    pathTestShort: 'nope',
                    pathTestAsterix: 'nope',
                    pathTestPlaceholder: 'nope',
                    domainWildcard: 'nope',
                    domainWildcardNope: 'nope',
                    invalidCheck: 'nope',
                    conditionalChanges: [
                        {
                            domain: 'example.com',
                            patchSettings: [
                                { op: 'replace', path: '/test', value: 'enabled2' },
                                { op: 'replace', path: '/otherTest', value: 'enabled' },
                            ],
                        },
                        {
                            domain: 'beep.example.com',
                            patchSettings: [{ op: 'replace', path: '/test', value: 'enabled3' }],
                        },
                        {
                            domain: ['meep.com', 'example.com'],
                            patchSettings: [{ op: 'replace', path: '/arrayTest', value: 'enabledArray' }],
                        },
                        {
                            condition: {
                                urlPattern: {
                                    path: '/path/path/me',
                                },
                            },
                            patchSettings: [{ op: 'replace', path: '/pathTest', value: 'beep' }],
                        },
                        {
                            condition: {
                                urlPattern: {
                                    hostname: 'beep.nope.com',
                                    path: '/path/path/me',
                                },
                            },
                            patchSettings: [{ op: 'replace', path: '/pathTestNotApply', value: 'yep' }],
                        },
                        {
                            condition: {
                                urlPattern: 'http://beep.example.com/path/path/me',
                            },
                            patchSettings: [{ op: 'replace', path: '/pathTestShort', value: 'beep' }],
                        },
                        {
                            condition: {
                                urlPattern: 'http://beep.example.com/*/path/me',
                            },
                            patchSettings: [{ op: 'replace', path: '/pathTestAsterix', value: 'comic' }],
                        },
                        {
                            condition: {
                                urlPattern: 'http://beep.example.com/:something/path/me',
                            },
                            patchSettings: [{ op: 'replace', path: '/pathTestPlaceholder', value: 'place' }],
                        },
                        {
                            condition: {
                                urlPattern: 'http://beep.*.com/*/path/me',
                            },
                            patchSettings: [{ op: 'replace', path: '/domainWildcard', value: 'wildwest' }],
                        },
                        {
                            condition: {
                                urlPattern: 'http://nope.*.com/*/path/me',
                            },
                            patchSettings: [{ op: 'replace', path: '/domainWildcardNope', value: 'wildwest' }],
                        },
                        {
                            condition: {
                                somethingInvalid: true,
                                urlPattern: 'http://beep.example.com/*/path/me',
                            },
                            patchSettings: [{ op: 'replace', path: '/invalidCheck', value: 'neverhappened' }],
                        },
                    ],
                },
            },
        };
        const me = new MyTestFeature2('test', {}, args);
        me.callInit(args);
        expect(didRun).withContext('Should run').toBeTrue();
    });

    it('Should trigger getFeatureSetting for the correct conditions', () => {
        let didRun = false;
        class MyTestFeature3 extends ContentFeature {
            init() {
                expect(this.getFeatureSetting('test')).toBe('enabled');
                expect(this.getFeatureSetting('otherTest')).toBe('disabled');
                expect(this.getFeatureSetting('test2')).toBe('noop');
                expect(this.getFeatureSetting('otherTest2')).toBe('me');
                expect(this.getFeatureSetting('test3')).toBe('yep');
                expect(this.getFeatureSetting('otherTest3')).toBe('expected');
                expect(this.getFeatureSetting('test4')).toBe('yep');
                expect(this.getFeatureSetting('otherTest4')).toBe('expected');
                expect(this.getFeatureSetting('test5')).toBe('yep');
                expect(this.getFeatureSetting('otherTest5')).toBe('expected');
                didRun = true;
            }
        }

        const args = {
            site: {
                domain: 'beep.example.com',
                url: 'http://beep.example.com/path/path/me',
            },
            featureSettings: {
                test: {
                    test: 'enabled',
                    otherTest: 'disabled',
                    test4: 'yep',
                    otherTest4: 'expected',
                    conditionalChanges: [
                        {
                            condition: {
                                // This array case is unsupported currently.
                                domain: ['example.com'],
                            },
                            patchSettings: [
                                { op: 'replace', path: '/test', value: 'enabled2' },
                                { op: 'replace', path: '/otherTest', value: 'bloop' },
                            ],
                        },
                        {
                            condition: [
                                {
                                    domain: 'example.com',
                                },
                                {
                                    domain: 'other.com',
                                },
                            ],
                            patchSettings: [
                                { op: 'replace', path: '/test2', value: 'noop' },
                                { op: 'replace', path: '/otherTest2', value: 'me' },
                            ],
                        },
                        {
                            condition: [
                                {
                                    urlPattern: '*://*.example.com',
                                },
                                {
                                    urlPattern: '*://other.com',
                                },
                            ],
                            patchSettings: [
                                { op: 'replace', path: '/test3', value: 'yep' },
                                { op: 'replace', path: '/otherTest3', value: 'expected' },
                            ],
                        },
                        {
                            condition: [
                                {
                                    // This is at the apex so should not match
                                    urlPattern: '*://example.com',
                                },
                                {
                                    urlPattern: '*://other.com',
                                },
                            ],
                            patchSettings: [
                                { op: 'replace', path: '/test4', value: 'nope' },
                                { op: 'replace', path: '/otherTest4', value: 'notexpected' },
                            ],
                        },
                        {
                            condition: [
                                {
                                    urlPattern: {
                                        hostname: '*.example.com',
                                    },
                                },
                            ],
                            patchSettings: [
                                { op: 'replace', path: '/test5', value: 'yep' },
                                { op: 'replace', path: '/otherTest5', value: 'expected' },
                            ],
                        },
                    ],
                },
            },
        };
        const me = new MyTestFeature3('test', {}, args);
        me.callInit(args);
        expect(didRun).withContext('Should run').toBeTrue();
    });
    it('Should respect minSupportedVersion as a condition', () => {
        let didRun = false;
        class MyTestFeature3 extends ContentFeature {
            init() {
                expect(this.getFeatureSetting('aiChat')).toBe('enabled');
                expect(this.getFeatureSetting('subscriptions')).toBe('disabled');
                didRun = true;
            }
        }

        const args = {
            site: {
                domain: 'example.com',
                url: 'http://example.com',
            },
            platform: {
                version: '1.1.0',
            },
            bundledConfig: {
                features: {
                    test: {
                        state: 'enabled',
                        exceptions: [],
                        settings: {
                            aiChat: 'disabled',
                            subscriptions: 'disabled',
                            conditionalChanges: [
                                {
                                    condition: {
                                        domain: 'example.com',
                                        minSupportedVersion: '1.1.0',
                                    },
                                    patchSettings: [
                                        {
                                            op: 'replace',
                                            path: '/aiChat',
                                            value: 'enabled',
                                        },
                                    ],
                                },
                                {
                                    condition: {
                                        domain: 'example.com',
                                        minSupportedVersion: '1.2.0',
                                    },
                                    patchSettings: [
                                        {
                                            op: 'replace',
                                            path: '/subscriptions',
                                            value: 'enabled',
                                        },
                                    ],
                                },
                            ],
                        },
                    },
                },
                unprotectedTemporary: [],
            },
        };
        const me = new MyTestFeature3('test', {}, args);
        me.callInit(args);
        expect(didRun).withContext('Should run').toBeTrue();
    });

    describe('addDebugFlag', () => {
        class MyTestFeature extends ContentFeature {
            // eslint-disable-next-line
            // @ts-ignore partial mock
            messaging = {
                notify(_name, _data) {},
            };
        }
        let feature;
        beforeEach(() => {
            feature = new MyTestFeature('someFeatureName', {}, {});
        });

        it('should not send duplicate flags', () => {
            // send some flag
            feature.addDebugFlag('someflag');
            // send it again
            const spyNotify = spyOn(feature.messaging, 'notify');
            feature.addDebugFlag('someflag');
            expect(spyNotify).not.toHaveBeenCalled();
        });

        it('should send an empty suffix by default', () => {
            const spyNotify = spyOn(feature.messaging, 'notify');
            feature.addDebugFlag();
            expect(spyNotify).toHaveBeenCalledWith('addDebugFlag', {
                flag: 'someFeatureName',
            });
        });
    });

    describe('defineProperty', () => {
        class MyTestFeature extends ContentFeature {
            addDebugFlag() {
                this.debugFlagAdded = true;
            }
        }
        let feature;
        beforeEach(() => {
            feature = new MyTestFeature('someFeatureName', {}, {});
        });

        it('should add debug flag to value descriptors', () => {
            const object = {};
            feature.defineProperty(object, 'someProp', {
                value: () => 'someValue',
                writable: true,
                enumerable: true,
                configurable: true,
            });
            expect(feature.debugFlagAdded).toBeUndefined();
            expect(object.someProp()).toBe('someValue');
            const newDesc = Object.getOwnPropertyDescriptor(object, 'someProp');
            expect(newDesc).toBeDefined();
            // @ts-expect-error - this must be defined
            newDesc.value = null;
            expect(newDesc).toEqual({
                value: null,
                writable: true,
                enumerable: true,
                configurable: true,
            });
            expect(feature.debugFlagAdded).toBeTrue();
        });

        it('should add debug flag to get descriptors', () => {
            const object = {};
            feature.defineProperty(object, 'someProp', {
                get: () => 'someValue',
                enumerable: true,
                configurable: true,
            });
            expect(feature.debugFlagAdded).toBeUndefined();
            expect(object.someProp).toBe('someValue');
            const newDesc = Object.getOwnPropertyDescriptor(object, 'someProp');
            expect(newDesc).toBeDefined();
            // @ts-expect-error - this must be defined
            newDesc.get = null;
            expect(newDesc).toEqual({
                // @ts-expect-error get is overridden
                get: null,
                set: undefined,
                enumerable: true,
                configurable: true,
            });
            expect(feature.debugFlagAdded).toBeTrue();
        });

        it('should add debug flag to set descriptors', () => {
            const object = {};
            feature.defineProperty(object, 'someProp', {
                set: () => {},
                enumerable: true,
                configurable: true,
            });
            expect(feature.debugFlagAdded).toBeUndefined();
            expect((object.someProp = 'someValue')).toBe('someValue');
            const newDesc = Object.getOwnPropertyDescriptor(object, 'someProp');
            expect(newDesc).toBeDefined();
            // @ts-expect-error - this must be defined
            newDesc.set = null;
            expect(newDesc).toEqual({
                get: undefined,
                // @ts-expect-error set is overridden
                set: null,
                enumerable: true,
                configurable: true,
            });
            expect(feature.debugFlagAdded).toBeTrue();
        });

        it('should not change toString()', () => {
            const object = {};
            const fn = () => 'someValue';
            feature.defineProperty(object, 'someProp', {
                value: fn,
                writable: true,
                enumerable: true,
                configurable: true,
            });
            expect(object.someProp()).toBe('someValue');
            expect(object.someProp.toString()).toBe(fn.toString());
            expect(Object.prototype.toString.apply(object.someProp)).toBe(Object.prototype.toString.apply(fn));
            expect(`${object.someProp}`).toBe(`${fn}`);
            expect(object.someProp.toString.toString()).toBe(fn.toString.toString());
            // we don't expect it to wrap toString() more than 2 levels deep
            expect(object.someProp.toString.toString.toString()).not.toBe(fn.toString.toString.toString());
        });
    });
});
