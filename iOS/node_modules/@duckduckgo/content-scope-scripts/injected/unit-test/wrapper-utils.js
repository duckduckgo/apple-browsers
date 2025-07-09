import { shimInterface, shimProperty } from '../src/wrapper-utils.js';

describe('Shim API', () => {
    // MediaSession is just an example, to make it close to reality
    /** @type {typeof MediaSession} */
    let MyMediaSession;

    let definePropertyFn;
    let navigatorPrototype;
    let navigator;

    beforeEach(() => {
        expect(globalThis.MediaSession).toBeUndefined();
        MyMediaSession = class {
            metadata = null;
            /** @type {MediaSession['playbackState']} */
            playbackState = 'none';

            setActionHandler() {
                return 123;
            }

            setCameraActive() {}
            setMicrophoneActive() {}
            setPositionState() {}
        };
        definePropertyFn = spyOn(Object, 'defineProperty').and.callThrough();

        navigatorPrototype = {};
        function NavigatorConstructor() {}
        NavigatorConstructor.prototype = navigatorPrototype;
        navigator = new NavigatorConstructor();
    });

    afterEach(() => {
        // @ts-expect-error globalThis is read-only
        delete globalThis.MediaSession;
    });

    describe('shimInterface()', () => {
        it('should (re)define the global', () => {
            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    wrapToString: true,
                    disallowConstructor: false,
                    allowConstructorCall: false,
                },
                definePropertyFn,
            );
            expect(definePropertyFn).toHaveBeenCalledTimes(2);
            const NewMediaSession = globalThis.MediaSession;
            expect(NewMediaSession).toBeDefined();
            const newPropertyDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'MediaSession');

            expect({ ...newPropertyDescriptor, value: null })
                .withContext('property descriptors should match')
                .toEqual({ value: null, writable: true, enumerable: false, configurable: true });
            expect(NewMediaSession.name).toBe('MediaSession');

            expect(new MyMediaSession() instanceof NewMediaSession)
                .withContext('instances should pass the instanceof check')
                .toBeTrue();
            expect(new NewMediaSession() instanceof NewMediaSession)
                .withContext('instances should pass the instanceof check')
                .toBeTrue();
        });

        it('should support disallowConstructor', () => {
            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    disallowConstructor: false,
                    allowConstructorCall: false,
                    wrapToString: true,
                },
                definePropertyFn,
            );
            expect(() => new globalThis.MediaSession()).not.toThrow();

            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    disallowConstructor: true,
                    allowConstructorCall: false,
                    wrapToString: true,
                },
                definePropertyFn,
            );
            expect(() => new globalThis.MediaSession()).toThrowError(TypeError);

            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    disallowConstructor: true,
                    constructorErrorMessage: 'friendly message',
                    allowConstructorCall: false,
                    wrapToString: true,
                },
                definePropertyFn,
            );
            expect(() => new globalThis.MediaSession()).toThrowMatching(
                (err) => err instanceof TypeError && err.message === 'friendly message',
            );
        });

        it('should support allowConstructorCall', () => {
            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    allowConstructorCall: true,
                    wrapToString: true,
                    disallowConstructor: false,
                },
                definePropertyFn,
            );
            // @ts-expect-error real MediaSession is not callable
            expect(() => globalThis.MediaSession()).not.toThrow();
            // @ts-expect-error real MediaSession is not callable
            expect(globalThis.MediaSession() instanceof globalThis.MediaSession)
                .withContext('instances should pass the instanceof check')
                .toBeTrue();

            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    allowConstructorCall: false,
                    wrapToString: true,
                    disallowConstructor: false,
                },
                definePropertyFn,
            );
            // @ts-expect-error real MediaSession is not callable
            expect(() => globalThis.MediaSession()).toThrowError(TypeError);
        });

        it('should support wrapToString', () => {
            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    wrapToString: false,
                    disallowConstructor: false,
                    allowConstructorCall: false,
                },
                definePropertyFn,
            );
            expect(globalThis.MediaSession.toString()).not.toContain('class');
            expect(globalThis.MediaSession.toString.toString())
                .withContext("Shim's toString.toString() should not be masked")
                .toBe(MyMediaSession.toString.toString());
            expect(globalThis.MediaSession.prototype.setActionHandler.toString())
                .withContext("Shim's method's .toString() should not be masked")
                .toBe(MyMediaSession.prototype.setActionHandler.toString());

            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    wrapToString: true,
                    disallowConstructor: false,
                    allowConstructorCall: false,
                },
                definePropertyFn,
            );

            expect(globalThis.MediaSession.toString()).toBe('function MediaSession() { [native code] }');
            expect(globalThis.MediaSession.toString.toString()).toBe('function toString() { [native code] }');
            expect(globalThis.MediaSession.prototype.setActionHandler.toString()).toBe('function setActionHandler() { [native code] }');
        });
    });

    describe('shimProperty()', () => {
        it('should correctly shim the property', () => {
            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    wrapToString: true,
                    disallowConstructor: false,
                    allowConstructorCall: false,
                },
                definePropertyFn,
            );
            const instance = new MyMediaSession();
            shimProperty(navigatorPrototype, 'mediaSession', instance, false, definePropertyFn);

            const NewMediaSession = globalThis.MediaSession;
            expect(navigator.mediaSession instanceof NewMediaSession)
                .withContext('instances should pass the instanceof check')
                .toBeTrue();
            expect(navigator.mediaSession.setActionHandler()).withContext('method should return expected value').toBe(123);
            expect(navigator.mediaSession.toString()).toBe('[object MediaSession]');
            expect(navigator.mediaSession.toString.toString()).toBe('function toString() { [native code] }');
        });

        it('should support writable properties', () => {
            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    wrapToString: true,
                    disallowConstructor: false,
                    allowConstructorCall: false,
                },
                definePropertyFn,
            );
            const instance = new MyMediaSession();
            shimProperty(navigatorPrototype, 'mediaSession', instance, false, definePropertyFn);

            const descriptor = Object.getOwnPropertyDescriptor(navigatorPrototype, 'mediaSession');
            // @ts-expect-error we know it's defined
            descriptor.value = null;
            expect(descriptor).toEqual(
                {
                    value: null,
                    configurable: true,
                    enumerable: true,
                    writable: true,
                },
                'property should be writable',
            );
        });

        it('should support readonly properties', () => {
            shimInterface(
                'MediaSession',
                MyMediaSession,
                {
                    wrapToString: true,
                    disallowConstructor: false,
                    allowConstructorCall: false,
                },
                definePropertyFn,
            );
            const instance = new MyMediaSession();
            shimProperty(navigatorPrototype, 'mediaSession', instance, true, definePropertyFn);

            /** @type {import('../src/wrapper-utils').StrictAccessorDescriptor} */
            // @ts-expect-error we know it's defined
            const descriptor = Object.getOwnPropertyDescriptor(navigatorPrototype, 'mediaSession');

            expect(descriptor.get).toBeDefined();
            expect(descriptor.set).toBeUndefined();

            const getter = descriptor.get;

            // @ts-expect-error we know it's defined
            descriptor.get = null;
            expect(descriptor).toEqual({
                // @ts-expect-error get is overridden
                get: null,
                // @ts-expect-error set is overridden
                set: undefined,
                configurable: true,
                enumerable: true,
            });

            expect(getter.toString()).toBe('function get mediaSession() { [native code] }');
        });
    });
});
