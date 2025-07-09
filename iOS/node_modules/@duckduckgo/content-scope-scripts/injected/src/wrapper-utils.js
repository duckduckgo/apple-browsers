import {
    functionToString,
    getOwnPropertyDescriptor,
    getOwnPropertyDescriptors,
    objectDefineProperty,
    objectEntries,
    objectKeys,
} from './captured-globals.js';

// special property that is set on classes used to shim standard interfaces
export const ddgShimMark = Symbol('ddgShimMark');

/**
 * FIXME: this function is not needed anymore after FF xray removal
 * Like Object.defineProperty, but with support for Firefox's mozProxies.
 * @param {any} object - object whose property we are wrapping (most commonly a prototype, e.g. globalThis.BatteryManager.prototype)
 * @param {string} propertyName
 * @param {import('./wrapper-utils').StrictPropertyDescriptor} descriptor - requires all descriptor options to be defined because we can't validate correctness based on TS types
 */
export function defineProperty(object, propertyName, descriptor) {
    objectDefineProperty(object, propertyName, descriptor);
}

/**
 * return a proxy to `newFn` that fakes .toString() and .toString.toString() to resemble the `origFn`.
 * WARNING: do NOT proxy toString multiple times, as it will not work as expected.
 *
 * @param {*} newFn
 * @param {*} origFn
 * @param {string} [mockValue] - when provided, .toString() will return this value
 */
export function wrapToString(newFn, origFn, mockValue) {
    if (typeof newFn !== 'function' || typeof origFn !== 'function') {
        return newFn;
    }

    return new Proxy(newFn, { get: toStringGetTrap(origFn, mockValue) });
}

/**
 * generate a proxy handler trap that fakes .toString() and .toString.toString() to resemble the `targetFn`.
 * Note that it should be used as the get() trap.
 * @param {*} targetFn
 * @param {string} [mockValue] - when provided, .toString() will return this value
 * @returns { (target: any, prop: string, receiver: any) => any }
 */
export function toStringGetTrap(targetFn, mockValue) {
    // We wrap two levels deep to handle toString.toString() calls
    return function get(target, prop, receiver) {
        if (prop === 'toString') {
            const origToString = Reflect.get(targetFn, 'toString', targetFn);
            const toStringProxy = new Proxy(origToString, {
                apply(target, thisArg, argumentsList) {
                    // only mock toString() when called on the proxy itself. If the method is applied to some other object, it should behave as a normal toString()
                    if (thisArg === receiver) {
                        if (mockValue) {
                            return mockValue;
                        }
                        return Reflect.apply(target, targetFn, argumentsList);
                    } else {
                        return Reflect.apply(target, thisArg, argumentsList);
                    }
                },
                get(target, prop, receiver) {
                    // handle toString.toString() result
                    if (prop === 'toString') {
                        const origToStringToString = Reflect.get(origToString, 'toString', origToString);
                        const toStringToStringProxy = new Proxy(origToStringToString, {
                            apply(target, thisArg, argumentsList) {
                                if (thisArg === toStringProxy) {
                                    return Reflect.apply(target, origToString, argumentsList);
                                } else {
                                    return Reflect.apply(target, thisArg, argumentsList);
                                }
                            },
                        });
                        return toStringToStringProxy;
                    }
                    return Reflect.get(target, prop, receiver);
                },
            });
            return toStringProxy;
        }
        return Reflect.get(target, prop, receiver);
    };
}

/**
 * Wrap functions to fix toString but also behave as closely to their real function as possible like .name and .length etc.
 * @param {*} functionValue
 * @param {*} realTarget
 * @returns {Proxy} a proxy for the function
 */
export function wrapFunction(functionValue, realTarget) {
    return new Proxy(realTarget, {
        get(target, prop, receiver) {
            if (prop === 'toString') {
                const method = Reflect.get(target, prop, receiver).bind(target);
                Object.defineProperty(method, 'toString', {
                    value: functionToString.bind(functionToString),
                    enumerable: false,
                });
                return method;
            }
            return Reflect.get(target, prop, receiver);
        },
        apply(_, thisArg, argumentsList) {
            // This is where we call our real function
            return Reflect.apply(functionValue, thisArg, argumentsList);
        },
    });
}

/**
 * Wrap a `get`/`set` or `value` property descriptor. Only for data properties. For methods, use wrapMethod(). For constructors, use wrapConstructor().
 * @param {any} object - object whose property we are wrapping (most commonly a prototype, e.g. globalThis.Screen.prototype)
 * @param {string} propertyName
 * @param {Partial<PropertyDescriptor>} descriptor
 * @param {typeof Object.defineProperty} definePropertyFn - function to use for defining the property
 * @returns {PropertyDescriptor|undefined} original property descriptor, or undefined if it's not found
 */
export function wrapProperty(object, propertyName, descriptor, definePropertyFn) {
    if (!object) {
        return;
    }

    /** @type {StrictPropertyDescriptor} */
    // @ts-expect-error - we check for undefined below
    const origDescriptor = getOwnPropertyDescriptor(object, propertyName);
    if (!origDescriptor) {
        // this happens if the property is not implemented in the browser
        return;
    }

    if (
        ('value' in origDescriptor && 'value' in descriptor) ||
        ('get' in origDescriptor && 'get' in descriptor) ||
        ('set' in origDescriptor && 'set' in descriptor)
    ) {
        definePropertyFn(object, propertyName, {
            ...origDescriptor,
            ...descriptor,
        });
        return origDescriptor;
    } else {
        // if the property is defined with get/set it must be wrapped with a get/set. If it's defined with a `value`, it must be wrapped with a `value`
        throw new Error(`Property descriptor for ${propertyName} may only include the following keys: ${objectKeys(origDescriptor)}`);
    }
}

/**
 * Wrap a method descriptor. Only for function properties. For data properties, use wrapProperty(). For constructors, use wrapConstructor().
 * @param {any} object - object whose property we are wrapping (most commonly a prototype, e.g. globalThis.Bluetooth.prototype)
 * @param {string} propertyName
 * @param {(originalFn, ...args) => any } wrapperFn - wrapper function receives the original function as the first argument
 * @param {DefinePropertyFn} definePropertyFn - function to use for defining the property
 * @returns {PropertyDescriptor|undefined} original property descriptor, or undefined if it's not found
 */
export function wrapMethod(object, propertyName, wrapperFn, definePropertyFn) {
    if (!object) {
        return;
    }

    /** @type {StrictPropertyDescriptor} */
    // @ts-expect-error - we check for undefined below
    const origDescriptor = getOwnPropertyDescriptor(object, propertyName);
    if (!origDescriptor) {
        // this happens if the property is not implemented in the browser
        return;
    }

    // @ts-expect-error - we check for undefined below
    const origFn = origDescriptor.value;
    if (!origFn || typeof origFn !== 'function') {
        // method properties are expected to be defined with a `value`
        throw new Error(`Property ${propertyName} does not look like a method`);
    }

    const newFn = wrapToString(function () {
        return wrapperFn.call(this, origFn, ...arguments);
    }, origFn);

    definePropertyFn(object, propertyName, {
        ...origDescriptor,
        value: newFn,
    });
    return origDescriptor;
}

/**
 * @template {keyof typeof globalThis} StandardInterfaceName
 * @param {StandardInterfaceName} interfaceName - the name of the interface to shim (must be some known standard API, e.g. 'MediaSession')
 * @param {typeof globalThis[StandardInterfaceName]} ImplClass - the class to use as the shim implementation
 * @param {DefineInterfaceOptions} options - options for defining the interface
 * @param {DefinePropertyFn} definePropertyFn - function to use for defining the property
 * @param {ImportMeta['injectName']} [injectName] - the name of the inject to use for the shim
 */
export function shimInterface(interfaceName, ImplClass, options, definePropertyFn, injectName) {
    if (injectName === 'integration') {
        if (!globalThis.origInterfaceDescriptors) globalThis.origInterfaceDescriptors = {};
        const descriptor = Object.getOwnPropertyDescriptor(globalThis, interfaceName);
        globalThis.origInterfaceDescriptors[interfaceName] = descriptor;

        globalThis.ddgShimMark = ddgShimMark;
    }

    /** @type {DefineInterfaceOptions} */
    const defaultOptions = {
        allowConstructorCall: false,
        disallowConstructor: false,
        constructorErrorMessage: 'Illegal constructor',
        wrapToString: true,
    };

    const fullOptions = {
        interfaceDescriptorOptions: { writable: true, enumerable: false, configurable: true, value: ImplClass },
        ...defaultOptions,
        ...options,
    };

    // In some cases we can get away without a full proxy, but in many cases below we need it.
    // For example, we can't redefine `prototype` property on ES6 classes.
    // Se we just always wrap the class to make the code more maintaibnable

    /** @type {ProxyHandler<Function>} */
    const proxyHandler = {};

    // handle the case where the constructor is called without new
    if (fullOptions.allowConstructorCall) {
        // make the constructor function callable without new
        proxyHandler.apply = function (target, _thisArg, argumentsList) {
            return Reflect.construct(target, argumentsList, target);
        };
    }

    // make the constructor function throw when called without new
    if (fullOptions.disallowConstructor) {
        proxyHandler.construct = function () {
            throw new TypeError(fullOptions.constructorErrorMessage);
        };
    }

    if (fullOptions.wrapToString) {
        // mask toString() on class methods. `ImplClass.prototype` is non-configurable: we can't override or proxy it, so we have to wrap each method individually
        for (const [prop, descriptor] of objectEntries(getOwnPropertyDescriptors(ImplClass.prototype))) {
            if (prop !== 'constructor' && descriptor.writable && typeof descriptor.value === 'function') {
                ImplClass.prototype[prop] = new Proxy(descriptor.value, {
                    get: toStringGetTrap(descriptor.value, `function ${prop}() { [native code] }`),
                });
            }
        }

        // wrap toString on the constructor function itself
        Object.assign(proxyHandler, {
            get: toStringGetTrap(ImplClass, `function ${interfaceName}() { [native code] }`),
        });
    }

    // Note that instanceof should still work, since the `.prototype` object is proxied too:
    // Interface() instanceof Interface === true
    // ImplClass() instanceof Interface === true
    const Interface = new Proxy(ImplClass, proxyHandler);

    // Make sure that Interface().constructor === Interface (not ImplClass)
    if (ImplClass.prototype?.constructor === ImplClass) {
        /** @type {StrictDataDescriptor} */
        // @ts-expect-error - As long as ImplClass is a normal class, it should have the prototype property
        const descriptor = getOwnPropertyDescriptor(ImplClass.prototype, 'constructor');
        if (descriptor.writable) {
            ImplClass.prototype.constructor = Interface;
        }
    }

    if (injectName === 'integration') {
        // mark the class as a shimmed class
        // we do it only in test mode, to avoid potential side effects in production. See the playwright test in integration-test/test-pages/webcompat/pages/shims.html
        definePropertyFn(ImplClass, ddgShimMark, {
            value: true,
            configurable: false,
            enumerable: false,
            writable: false,
        });
    }

    // mock the name property
    definePropertyFn(ImplClass, 'name', {
        value: interfaceName,
        configurable: true,
        enumerable: false,
        writable: false,
    });

    // interfaces are exposed directly on the global object, not on its prototype
    definePropertyFn(globalThis, interfaceName, { ...fullOptions.interfaceDescriptorOptions, value: Interface });
}

/**
 * Define a missing standard property on a global (prototype) object. Only for data properties.
 * For constructors, use shimInterface().
 * Most of the time, you'd want to call shimInterface() first to shim the class itself (MediaSession), and then shimProperty() for the global singleton instance (Navigator.prototype.mediaSession).
 * @template Base
 * @template {keyof Base & string} K
 * @param {Base} baseObject - object whose property we are shimming (most commonly a prototype object, e.g. Navigator.prototype)
 * @param {K} propertyName - name of the property to shim (e.g. 'mediaSession')
 * @param {Base[K]} implInstance - instance to use as the shim (e.g. new MyMediaSession())
 * @param {boolean} readOnly - whether the property should be read-only
 * @param {DefinePropertyFn} definePropertyFn - function to use for defining the property
 * @param {ImportMeta['injectName']} [injectName] - the name of the inject to use for the shim
 */
export function shimProperty(baseObject, propertyName, implInstance, readOnly, definePropertyFn, injectName) {
    // @ts-expect-error - implInstance is a class instance
    const ImplClass = implInstance.constructor;

    if (injectName === 'integration') {
        if (!globalThis.origPropDescriptors) globalThis.origPropDescriptors = [];
        const descriptor = Object.getOwnPropertyDescriptor(baseObject, propertyName);
        globalThis.origPropDescriptors.push([baseObject, propertyName, descriptor]);

        globalThis.ddgShimMark = ddgShimMark;
        if (ImplClass[ddgShimMark] !== true) {
            throw new TypeError('implInstance must be an instance of a shimmed class');
        }
    }

    // mask toString() and toString.toString() on the instance
    const proxiedInstance = new Proxy(implInstance, {
        get: toStringGetTrap(implInstance, `[object ${ImplClass.name}]`),
    });

    /** @type {StrictPropertyDescriptor} */
    let descriptor;

    // Note that we only cover most common cases: a getter for "readonly" properties, and a value descriptor for writable properties.
    // But there could be other cases, e.g. a property with both a getter and a setter. These could be defined with a raw defineProperty() call.
    // Important: make sure to cover each new shim with a test that verifies that all descriptors match the standard API.
    if (readOnly) {
        const getter = function get() {
            return proxiedInstance;
        };
        const proxiedGetter = new Proxy(getter, {
            get: toStringGetTrap(getter, `function get ${propertyName}() { [native code] }`),
        });
        descriptor = {
            configurable: true,
            enumerable: true,
            get: proxiedGetter,
        };
    } else {
        descriptor = {
            configurable: true,
            enumerable: true,
            writable: true,
            value: proxiedInstance,
        };
    }

    definePropertyFn(baseObject, propertyName, descriptor);
}

/**
 * @callback DefinePropertyFn
 * @param {object} baseObj
 * @param {PropertyKey} propertyName
 * @param {StrictPropertyDescriptor} descriptor
 * @returns {object}
 */

/**
 * @typedef {Object} BaseStrictPropertyDescriptor
 * @property {boolean} configurable
 * @property {boolean} enumerable
 */

/**
 * @typedef {BaseStrictPropertyDescriptor & { value: any; writable: boolean }} StrictDataDescriptor
 * @typedef {BaseStrictPropertyDescriptor & { get: () => any; set: (v: any) => void }} StrictAccessorDescriptor
 * @typedef {BaseStrictPropertyDescriptor & { get: () => any }} StrictGetDescriptor
 * @typedef {BaseStrictPropertyDescriptor & { set: (v: any) => void }} StrictSetDescriptor
 * @typedef {StrictDataDescriptor | StrictAccessorDescriptor | StrictGetDescriptor | StrictSetDescriptor} StrictPropertyDescriptor
 */

/**
 * @typedef {Object} BaseDefineInterfaceOptions
 * @property {string} [constructorErrorMessage]
 * @property {boolean} wrapToString
 */

/**
 * @typedef {{ allowConstructorCall: true; disallowConstructor: false }} DefineInterfaceOptionsWithAllowConstructorCallMixin
 */

/**
 * @typedef {{ allowConstructorCall: false; disallowConstructor: true }} DefineInterfaceOptionsWithDisallowConstructorMixin
 */

/**
 * @typedef {{ allowConstructorCall: false; disallowConstructor: false }} DefineInterfaceOptionsDefaultMixin
 */

/**
 * @typedef {BaseDefineInterfaceOptions & (DefineInterfaceOptionsWithAllowConstructorCallMixin | DefineInterfaceOptionsWithDisallowConstructorMixin | DefineInterfaceOptionsDefaultMixin)} DefineInterfaceOptions
 */
