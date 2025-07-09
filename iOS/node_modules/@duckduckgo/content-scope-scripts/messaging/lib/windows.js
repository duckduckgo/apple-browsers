/**
 * A wrapper for messaging on Windows.
 *
 * This requires 3 methods to be available, see {@link WindowsMessagingConfig} for details
 *
 * @document messaging/lib/examples/windows.example.js
 *
 */
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { MessagingTransport, NotificationMessage, RequestMessage } from '../index.js';

/**
 * An implementation of {@link MessagingTransport} for Windows
 *
 * All messages go through `window.chrome.webview` APIs
 *
 * @implements {MessagingTransport}
 */
export class WindowsMessagingTransport {
    /**
     * @param {WindowsMessagingConfig} config
     * @param {import('../index.js').MessagingContext} messagingContext
     * @internal
     */
    constructor(config, messagingContext) {
        this.messagingContext = messagingContext;
        this.config = config;
        this.globals = {
            window,
            JSONparse: window.JSON.parse,
            JSONstringify: window.JSON.stringify,
            Promise: window.Promise,
            Error: window.Error,
            String: window.String,
        };
        for (const [methodName, fn] of Object.entries(this.config.methods)) {
            if (typeof fn !== 'function') {
                throw new Error('cannot create WindowsMessagingTransport, missing the method: ' + methodName);
            }
        }
    }

    /**
     * @param {import('../index.js').NotificationMessage} msg
     */
    notify(msg) {
        const data = this.globals.JSONparse(this.globals.JSONstringify(msg.params || {}));
        const notification = WindowsNotification.fromNotification(msg, data);
        this.config.methods.postMessage(notification);
    }

    /**
     * @param {import('../index.js').RequestMessage} msg
     * @param {{signal?: AbortSignal}} opts
     * @return {Promise<any>}
     */
    request(msg, opts = {}) {
        // convert the message to window-specific naming
        const data = this.globals.JSONparse(this.globals.JSONstringify(msg.params || {}));
        const outgoing = WindowsRequestMessage.fromRequest(msg, data);

        // send the message
        this.config.methods.postMessage(outgoing);

        // compare incoming messages against the `msg.id`
        const comparator = (eventData) => {
            return eventData.featureName === msg.featureName && eventData.context === msg.context && eventData.id === msg.id;
        };

        /**
         * @param data
         * @return {data is import('../index.js').MessageResponse}
         */
        function isMessageResponse(data) {
            if ('result' in data) return true;
            if ('error' in data) return true;
            return false;
        }

        // now wait for a matching message
        return new this.globals.Promise((resolve, reject) => {
            try {
                this._subscribe(comparator, opts, (value, unsubscribe) => {
                    unsubscribe();

                    if (!isMessageResponse(value)) {
                        console.warn('unknown response type', value);
                        return reject(new this.globals.Error('unknown response'));
                    }

                    if (value.result) {
                        return resolve(value.result);
                    }

                    const message = this.globals.String(value.error?.message || 'unknown error');
                    reject(new this.globals.Error(message));
                });
            } catch (e) {
                reject(e);
            }
        });
    }

    /**
     * @param {import('../index.js').Subscription} msg
     * @param {(value: unknown | undefined) => void} callback
     */
    subscribe(msg, callback) {
        // compare incoming messages against the `msg.subscriptionName`
        const comparator = (eventData) => {
            return (
                eventData.featureName === msg.featureName &&
                eventData.context === msg.context &&
                eventData.subscriptionName === msg.subscriptionName
            );
        };

        // only forward the 'params' from a SubscriptionEvent
        const cb = (eventData) => {
            return callback(eventData.params);
        };

        // now listen for matching incoming messages.
        return this._subscribe(comparator, {}, cb);
    }

    /**
     * @typedef {import('../index.js').MessageResponse | import('../index.js').SubscriptionEvent} Incoming
     */
    /**
     * @param {(eventData: any) => boolean} comparator
     * @param {{signal?: AbortSignal}} options
     * @param {(value: Incoming, unsubscribe: (()=>void)) => void} callback
     * @internal
     */
    _subscribe(comparator, options, callback) {
        // if already aborted, reject immediately
        if (options?.signal?.aborted) {
            throw new DOMException('Aborted', 'AbortError');
        }
        /** @type {(()=>void) | undefined} */
        // eslint-disable-next-line prefer-const
        let teardown;

        /**
         * @param {MessageEvent} event
         */
        const idHandler = (event) => {
            if (this.messagingContext.env === 'production') {
                if (event.origin !== null && event.origin !== undefined) {
                    console.warn('ignoring because evt.origin is not `null` or `undefined`');
                    return;
                }
            }
            if (!event.data) {
                console.warn('data absent from message');
                return;
            }
            if (comparator(event.data)) {
                if (!teardown) throw new Error('unreachable');
                callback(event.data, teardown);
            }
        };

        // what to do if this promise is aborted
        const abortHandler = () => {
            teardown?.();
            throw new DOMException('Aborted', 'AbortError');
        };

        // console.log('DEBUG: handler setup', { config, comparator })

        this.config.methods.addEventListener('message', idHandler);
        options?.signal?.addEventListener('abort', abortHandler);

        teardown = () => {
            // console.log('DEBUG: handler teardown', { config, comparator })

            this.config.methods.removeEventListener('message', idHandler);
            options?.signal?.removeEventListener('abort', abortHandler);
        };

        return () => {
            teardown?.();
        };
    }
}

/**
 * To construct this configuration object, you need access to 3 methods
 *
 * - `postMessage`
 * - `addEventListener`
 * - `removeEventListener`
 *
 * These would normally be available on Windows via the following:
 *
 * - `window.chrome.webview.postMessage`
 * - `window.chrome.webview.addEventListener`
 * - `window.chrome.webview.removeEventListener`
 *
 * Depending on where the script is running, we may want to restrict access to those globals. On the native
 * side those handlers `window.chrome.webview` handlers might be deleted and replaces with in-scope variables, such as:
 *
 * [Example](./examples/windows.example.js)
 *
 */
export class WindowsMessagingConfig {
    /**
     * @param {object} params
     * @param {WindowsInteropMethods} params.methods
     * @internal
     */
    constructor(params) {
        /**
         * The methods required for communication
         */
        this.methods = params.methods;
        /**
         * @type {'windows'}
         */
        this.platform = 'windows';
    }
}

/**
 * These are the required methods
 */
export class WindowsInteropMethods {
    /**
     * @param {object} params
     * @param {Window['postMessage']} params.postMessage
     * @param {Window['addEventListener']} params.addEventListener
     * @param {Window['removeEventListener']} params.removeEventListener
     */
    constructor(params) {
        this.postMessage = params.postMessage;
        this.addEventListener = params.addEventListener;
        this.removeEventListener = params.removeEventListener;
    }
}

/**
 * This data type represents a message sent to the Windows
 * platform via `window.chrome.webview.postMessage`.
 *
 * **NOTE**: This is sent when a response is *not* expected
 */
export class WindowsNotification {
    /**
     * @param {object} params
     * @param {string} params.Feature
     * @param {string} params.SubFeatureName
     * @param {string} params.Name
     * @param {Record<string, any>} [params.Data]
     * @internal
     */
    constructor(params) {
        /**
         * Alias for: {@link NotificationMessage.context}
         */
        this.Feature = params.Feature;
        /**
         * Alias for: {@link NotificationMessage.featureName}
         */
        this.SubFeatureName = params.SubFeatureName;
        /**
         * Alias for: {@link NotificationMessage.method}
         */
        this.Name = params.Name;
        /**
         * Alias for: {@link NotificationMessage.params}
         */
        this.Data = params.Data;
    }

    /**
     * Helper to convert a {@link NotificationMessage} to a format that Windows can support
     * @param {NotificationMessage} notification
     * @returns {WindowsNotification}
     */
    static fromNotification(notification, data) {
        /** @type {WindowsNotification} */
        const output = {
            Data: data,
            Feature: notification.context,
            SubFeatureName: notification.featureName,
            Name: notification.method,
        };
        return output;
    }
}

/**
 * This data type represents a message sent to the Windows
 * platform via `window.chrome.webview.postMessage` when it
 * expects a response
 */
export class WindowsRequestMessage {
    /**
     * @param {object} params
     * @param {string} params.Feature
     * @param {string} params.SubFeatureName
     * @param {string} params.Name
     * @param {Record<string, any>} [params.Data]
     * @param {string} [params.Id]
     * @internal
     */
    constructor(params) {
        this.Feature = params.Feature;
        this.SubFeatureName = params.SubFeatureName;
        this.Name = params.Name;
        this.Data = params.Data;
        this.Id = params.Id;
    }

    /**
     * Helper to convert a {@link RequestMessage} to a format that Windows can support
     * @param {RequestMessage} msg
     * @param {Record<string, any>} data
     * @returns {WindowsRequestMessage}
     */
    static fromRequest(msg, data) {
        /** @type {WindowsRequestMessage} */
        const output = {
            Data: data,
            Feature: msg.context,
            SubFeatureName: msg.featureName,
            Name: msg.method,
            Id: msg.id,
        };
        return output;
    }
}
