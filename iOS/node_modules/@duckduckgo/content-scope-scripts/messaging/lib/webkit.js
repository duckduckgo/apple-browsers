/**
 *
 * A wrapper for messaging on WebKit platforms. It supports modern WebKit messageHandlers
 * along with encryption for older versions (like macOS Catalina)
 *
 * Note: If you wish to support Catalina then you'll need to implement the native
 * part of the message handling, see {@link WebkitMessagingTransport} for details.
 */
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { MessagingTransport, MissingHandler } from '../index.js';
import { isResponseFor, isSubscriptionEventFor } from '../schema.js';

/**
 * @example
 * On macOS 11+, this will just call through to `window.webkit.messageHandlers.x.postMessage`
 *
 * Eg: for a `foo` message defined in Swift that accepted the payload `{"bar": "baz"}`, the following
 * would occur:
 *
 * ```js
 * const json = await window.webkit.messageHandlers.foo.postMessage({ bar: "baz" });
 * const response = JSON.parse(json)
 * ```
 *
 * @example
 * On macOS 10 however, the process is a little more involved. A method will be appended to `window`
 * that allows the response to be delivered there instead. It's not exactly this, but you can visualize the flow
 * as being something along the lines of:
 *
 * ```js
 * // add the window method
 * window["_0123456"] = (response) => {
 *    // decrypt `response` and deliver the result to the caller here
 *    // then remove the temporary method
 *    delete window['_0123456']
 * };
 *
 * // send the data + `messageHanding` values
 * window.webkit.messageHandlers.foo.postMessage({
 *   bar: "baz",
 *   messagingHandling: {
 *     methodName: "_0123456",
 *     secret: "super-secret",
 *     key: [1, 2, 45, 2],
 *     iv: [34, 4, 43],
 *   }
 * });
 *
 * // later in swift, the following JavaScript snippet will be executed
 * (() => {
 *   window['_0123456']({
 *     ciphertext: [12, 13, 4],
 *     tag: [3, 5, 67, 56]
 *   })
 * })()
 * ```
 * @implements {MessagingTransport}
 */
export class WebkitMessagingTransport {
    /**
     * @param {WebkitMessagingConfig} config
     * @param {import('../index.js').MessagingContext} messagingContext
     */
    constructor(config, messagingContext) {
        this.messagingContext = messagingContext;
        this.config = config;
        this.globals = captureGlobals();
        if (!this.config.hasModernWebkitAPI) {
            this.captureWebkitHandlers(this.config.webkitMessageHandlerNames);
        }
    }

    /**
     * Sends message to the webkit layer (fire and forget)
     * @param {String} handler
     * @param {*} data
     * @internal
     */
    wkSend(handler, data = {}) {
        if (!(handler in this.globals.window.webkit.messageHandlers)) {
            throw new MissingHandler(`Missing webkit handler: '${handler}'`, handler);
        }
        if (!this.config.hasModernWebkitAPI) {
            const outgoing = {
                ...data,
                messageHandling: {
                    ...data.messageHandling,
                    secret: this.config.secret,
                },
            };
            if (!(handler in this.globals.capturedWebkitHandlers)) {
                throw new MissingHandler(`cannot continue, method ${handler} not captured on macos < 11`, handler);
            } else {
                return this.globals.capturedWebkitHandlers[handler](outgoing);
            }
        }
        return this.globals.window.webkit.messageHandlers[handler].postMessage?.(data);
    }

    /**
     * Sends message to the webkit layer and waits for the specified response
     * @param {String} handler
     * @param {import('../index.js').RequestMessage} data
     * @returns {Promise<*>}
     * @internal
     */
    async wkSendAndWait(handler, data) {
        if (this.config.hasModernWebkitAPI) {
            const response = await this.wkSend(handler, data);
            return this.globals.JSONparse(response || '{}');
        }

        try {
            const randMethodName = this.createRandMethodName();
            const key = await this.createRandKey();
            const iv = this.createRandIv();

            const { ciphertext, tag } = await new this.globals.Promise((/** @type {any} */ resolve) => {
                this.generateRandomMethod(randMethodName, resolve);

                // @ts-expect-error - this is a carve-out for catalina that will be removed soon
                data.messageHandling = new SecureMessagingParams({
                    methodName: randMethodName,
                    secret: this.config.secret,
                    key: this.globals.Arrayfrom(key),
                    iv: this.globals.Arrayfrom(iv),
                });
                this.wkSend(handler, data);
            });

            const cipher = new this.globals.Uint8Array([...ciphertext, ...tag]);
            const decrypted = await this.decrypt(cipher, key, iv);
            return this.globals.JSONparse(decrypted || '{}');
        } catch (e) {
            // re-throw when the error is just a 'MissingHandler'
            if (e instanceof MissingHandler) {
                throw e;
            } else {
                console.error('decryption failed', e);
                console.error(e);
                return { error: e };
            }
        }
    }

    /**
     * @param {import('../index.js').NotificationMessage} msg
     */
    notify(msg) {
        this.wkSend(msg.context, msg);
    }

    /**
     * @param {import('../index.js').RequestMessage} msg
     */
    async request(msg) {
        const data = await this.wkSendAndWait(msg.context, msg);

        if (isResponseFor(msg, data)) {
            if (data.result) {
                return data.result || {};
            }
            // forward the error if one was given explicity
            if (data.error) {
                throw new Error(data.error.message);
            }
        }

        throw new Error('an unknown error occurred');
    }

    /**
     * Generate a random method name and adds it to the global scope
     * The native layer will use this method to send the response
     * @param {string | number} randomMethodName
     * @param {Function} callback
     * @internal
     */
    generateRandomMethod(randomMethodName, callback) {
        this.globals.ObjectDefineProperty(this.globals.window, randomMethodName, {
            enumerable: false,
            // configurable, To allow for deletion later
            configurable: true,
            writable: false,
            /**
             * @param {any[]} args
             */
            value: (...args) => {
                callback(...args);
                delete this.globals.window[randomMethodName];
            },
        });
    }

    /**
     * @internal
     * @return {string}
     */
    randomString() {
        return '' + this.globals.getRandomValues(new this.globals.Uint32Array(1))[0];
    }

    /**
     * @internal
     * @return {string}
     */
    createRandMethodName() {
        return '_' + this.randomString();
    }

    /**
     * @type {{name: string, length: number}}
     * @internal
     */
    algoObj = {
        name: 'AES-GCM',
        length: 256,
    };

    /**
     * @returns {Promise<Uint8Array>}
     * @internal
     */
    async createRandKey() {
        const key = await this.globals.generateKey(this.algoObj, true, ['encrypt', 'decrypt']);
        const exportedKey = await this.globals.exportKey('raw', key);
        return new this.globals.Uint8Array(exportedKey);
    }

    /**
     * @returns {Uint8Array}
     * @internal
     */
    createRandIv() {
        return this.globals.getRandomValues(new this.globals.Uint8Array(12));
    }

    /**
     * @param {BufferSource} ciphertext
     * @param {BufferSource} key
     * @param {Uint8Array} iv
     * @returns {Promise<string>}
     * @internal
     */
    async decrypt(ciphertext, key, iv) {
        const cryptoKey = await this.globals.importKey('raw', key, 'AES-GCM', false, ['decrypt']);
        const algo = {
            name: 'AES-GCM',
            iv,
        };

        const decrypted = await this.globals.decrypt(algo, cryptoKey, ciphertext);

        const dec = new this.globals.TextDecoder();
        return dec.decode(decrypted);
    }

    /**
     * When required (such as on macos 10.x), capture the `postMessage` method on
     * each webkit messageHandler
     *
     * @param {string[]} handlerNames
     */
    captureWebkitHandlers(handlerNames) {
        const handlers = window.webkit.messageHandlers;
        if (!handlers) throw new MissingHandler('window.webkit.messageHandlers was absent', 'all');
        for (const webkitMessageHandlerName of handlerNames) {
            if (typeof handlers[webkitMessageHandlerName]?.postMessage === 'function') {
                /**
                 * `bind` is used here to ensure future calls to the captured
                 * `postMessage` have the correct `this` context
                 */
                const original = handlers[webkitMessageHandlerName];
                const bound = handlers[webkitMessageHandlerName].postMessage?.bind(original);
                this.globals.capturedWebkitHandlers[webkitMessageHandlerName] = bound;
                delete handlers[webkitMessageHandlerName].postMessage;
            }
        }
    }

    /**
     * @param {import('../index.js').Subscription} msg
     * @param {(value: unknown) => void} callback
     */
    subscribe(msg, callback) {
        // for now, bail if there's already a handler setup for this subscription
        if (msg.subscriptionName in this.globals.window) {
            throw new this.globals.Error(`A subscription with the name ${msg.subscriptionName} already exists`);
        }
        this.globals.ObjectDefineProperty(this.globals.window, msg.subscriptionName, {
            enumerable: false,
            configurable: true,
            writable: false,
            value: (data) => {
                if (data && isSubscriptionEventFor(msg, data)) {
                    callback(data.params);
                } else {
                    console.warn('Received a message that did not match the subscription', data);
                }
            },
        });
        return () => {
            this.globals.ReflectDeleteProperty(this.globals.window, msg.subscriptionName);
        };
    }
}

/**
 * Use this configuration to create an instance of {@link Messaging} for WebKit platforms
 *
 * We support modern WebKit environments *and* macOS Catalina.
 *
 * Please see {@link WebkitMessagingTransport} for details on how messages are sent/received
 *
 * [Example](./examples/webkit.example.js)
 */
export class WebkitMessagingConfig {
    /**
     * @param {object} params
     * @param {boolean} params.hasModernWebkitAPI
     * @param {string[]} params.webkitMessageHandlerNames
     * @param {string} params.secret
     * @internal
     */
    constructor(params) {
        /**
         * Whether or not the current WebKit Platform supports secure messaging
         * by default (eg: macOS 11+)
         */
        this.hasModernWebkitAPI = params.hasModernWebkitAPI;
        /**
         * A list of WebKit message handler names that a user script can send.
         *
         * For example, if the native platform can receive messages through this:
         *
         * ```js
         * window.webkit.messageHandlers.foo.postMessage('...')
         * ```
         *
         * then, this property would be:
         *
         * ```js
         * webkitMessageHandlerNames: ['foo']
         * ```
         */
        this.webkitMessageHandlerNames = params.webkitMessageHandlerNames;
        /**
         * A string provided by native platforms to be sent with future outgoing
         * messages.
         */
        this.secret = params.secret;
    }
}

/**
 * This is the additional payload that gets appended to outgoing messages.
 * It's used in the Swift side to encrypt the response that comes back
 */
export class SecureMessagingParams {
    /**
     * @param {object} params
     * @param {string} params.methodName
     * @param {string} params.secret
     * @param {number[]} params.key
     * @param {number[]} params.iv
     */
    constructor(params) {
        /**
         * The method that's been appended to `window` to be called later
         */
        this.methodName = params.methodName;
        /**
         * The secret used to ensure message sender validity
         */
        this.secret = params.secret;
        /**
         * The CipherKey as number[]
         */
        this.key = params.key;
        /**
         * The Initial Vector as number[]
         */
        this.iv = params.iv;
    }
}

/**
 * Capture some globals used for messaging handling to prevent page
 * scripts from tampering with this
 */
function captureGlobals() {
    // Create base with null prototype
    const globals = {
        window,
        getRandomValues: window.crypto.getRandomValues.bind(window.crypto),
        TextEncoder,
        TextDecoder,
        Uint8Array,
        Uint16Array,
        Uint32Array,
        JSONstringify: window.JSON.stringify,
        JSONparse: window.JSON.parse,
        Arrayfrom: window.Array.from,
        Promise: window.Promise,
        Error: window.Error,
        ReflectDeleteProperty: window.Reflect.deleteProperty.bind(window.Reflect),
        ObjectDefineProperty: window.Object.defineProperty,
        addEventListener: window.addEventListener.bind(window),
        /** @type {Record<string, any>} */
        capturedWebkitHandlers: {},
    };
    if (isSecureContext) {
        // skip for HTTP content since window.crypto.subtle is unavailable
        globals.generateKey = window.crypto.subtle.generateKey.bind(window.crypto.subtle);
        globals.exportKey = window.crypto.subtle.exportKey.bind(window.crypto.subtle);
        globals.importKey = window.crypto.subtle.importKey.bind(window.crypto.subtle);
        globals.encrypt = window.crypto.subtle.encrypt.bind(window.crypto.subtle);
        globals.decrypt = window.crypto.subtle.decrypt.bind(window.crypto.subtle);
    }
    return globals;
}
