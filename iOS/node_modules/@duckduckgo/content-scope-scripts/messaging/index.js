/**
 *
 * An abstraction for communications between JavaScript and host platforms.
 *
 * 1) First you construct your platform-specific configuration (eg: {@link WebkitMessagingConfig})
 * 2) Then use that to get an instance of the Messaging utility which allows
 * you to send and receive data in a unified way
 * 3) Each platform implements {@link MessagingTransport} along with its own Configuration
 *     - For example, to learn what configuration is required for Webkit, see: {@link WebkitMessagingConfig}
 *     - Or, to learn about how messages are sent and received in Webkit, see {@link WebkitMessagingTransport}
 *
 * ## Links
 * Please see the following links for examples
 *
 * - Windows: {@link WindowsMessagingConfig}
 * - Webkit: {@link WebkitMessagingConfig}
 * - Android: {@link AndroidMessagingConfig}
 * - Schema: {@link "Messaging Schema"}
 * - Implementation Guide: {@link "Messaging Implementation Guide"}
 *
 * @module Messaging
 */
import {
    WindowsMessagingConfig,
    WindowsMessagingTransport,
    WindowsInteropMethods,
    WindowsNotification,
    WindowsRequestMessage,
} from './lib/windows.js';
import { WebkitMessagingConfig, WebkitMessagingTransport } from './lib/webkit.js';
import { NotificationMessage, RequestMessage, Subscription, MessageResponse, MessageError, SubscriptionEvent } from './schema.js';
import { AndroidMessagingConfig, AndroidMessagingTransport } from './lib/android.js';
import { createTypedMessages } from './lib/typed-messages.js';

/**
 * Common options/config that are *not* transport specific.
 */
export class MessagingContext {
    /**
     * @param {object} params
     * @param {string} params.context
     * @param {string} params.featureName
     * @param {"production" | "development"} params.env
     * @internal
     */
    constructor(params) {
        this.context = params.context;
        this.featureName = params.featureName;
        this.env = params.env;
    }
}

/**
 * @typedef {WebkitMessagingConfig | WindowsMessagingConfig | AndroidMessagingConfig | TestTransportConfig} MessagingConfig
 */

/**
 *
 */
export class Messaging {
    /**
     * @param {MessagingContext} messagingContext
     * @param {MessagingConfig} config
     */
    constructor(messagingContext, config) {
        this.messagingContext = messagingContext;
        this.transport = getTransport(config, this.messagingContext);
    }

    /**
     * Send a 'fire-and-forget' message.
     * @throws {MissingHandler}
     *
     * @example
     *
     * ```ts
     * const messaging = new Messaging(config)
     * messaging.notify("foo", {bar: "baz"})
     * ```
     * @param {string} name
     * @param {Record<string, any>} [data]
     */
    notify(name, data = {}) {
        const message = new NotificationMessage({
            context: this.messagingContext.context,
            featureName: this.messagingContext.featureName,
            method: name,
            params: data,
        });
        this.transport.notify(message);
    }

    /**
     * Send a request, and wait for a response
     * @throws {MissingHandler}
     *
     * @example
     * ```
     * const messaging = new Messaging(config)
     * const response = await messaging.request("foo", {bar: "baz"})
     * ```
     *
     * @param {string} name
     * @param {Record<string, any>} [data]
     * @return {Promise<any>}
     */
    request(name, data = {}) {
        const id = globalThis?.crypto?.randomUUID?.() || name + '.response';
        const message = new RequestMessage({
            context: this.messagingContext.context,
            featureName: this.messagingContext.featureName,
            method: name,
            params: data,
            id,
        });
        return this.transport.request(message);
    }

    /**
     * @param {string} name
     * @param {(value: unknown) => void} callback
     * @return {() => void}
     */
    subscribe(name, callback) {
        const msg = new Subscription({
            context: this.messagingContext.context,
            featureName: this.messagingContext.featureName,
            subscriptionName: name,
        });
        return this.transport.subscribe(msg, callback);
    }
}

/**
 * @interface
 */
export class MessagingTransport {
    /**
     * @param {NotificationMessage} _msg
     * @returns {void}
     */

    notify(_msg) {
        throw new Error('must implement');
    }

    /**
     * @param {RequestMessage} _msg
     * @param {{signal?: AbortSignal}} [_options]
     * @return {Promise<any>}
     */

    request(_msg, _options = {}) {
        throw new Error('must implement');
    }

    /**
     * @param {Subscription} _msg
     * @param {(value: unknown) => void} _callback
     * @return {() => void}
     */

    subscribe(_msg, _callback) {
        throw new Error('must implement');
    }
}

/**
 * Use this to create testing transport on the fly.
 * It's useful for debugging, and for enabling scripts to run in
 * other environments - for example, testing in a browser without the need
 * for a full integration
 */
export class TestTransportConfig {
    /**
     * @param {MessagingTransport} impl
     */
    constructor(impl) {
        this.impl = impl;
    }
}

/**
 * @implements {MessagingTransport}
 */
export class TestTransport {
    /**
     * @param {TestTransportConfig} config
     * @param {MessagingContext} messagingContext
     */
    constructor(config, messagingContext) {
        this.config = config;
        this.messagingContext = messagingContext;
    }

    notify(msg) {
        return this.config.impl.notify(msg);
    }

    request(msg) {
        return this.config.impl.request(msg);
    }

    subscribe(msg, callback) {
        return this.config.impl.subscribe(msg, callback);
    }
}

/**
 * @param {WebkitMessagingConfig | WindowsMessagingConfig | AndroidMessagingConfig | TestTransportConfig} config
 * @param {MessagingContext} messagingContext
 * @returns {MessagingTransport}
 */
function getTransport(config, messagingContext) {
    if (config instanceof WebkitMessagingConfig) {
        return new WebkitMessagingTransport(config, messagingContext);
    }
    if (config instanceof WindowsMessagingConfig) {
        return new WindowsMessagingTransport(config, messagingContext);
    }
    if (config instanceof AndroidMessagingConfig) {
        return new AndroidMessagingTransport(config, messagingContext);
    }
    if (config instanceof TestTransportConfig) {
        return new TestTransport(config, messagingContext);
    }
    throw new Error('unreachable');
}

/**
 * Thrown when a handler cannot be found
 */
export class MissingHandler extends Error {
    /**
     * @param {string} message
     * @param {string} handlerName
     */
    constructor(message, handlerName) {
        super(message);
        this.handlerName = handlerName;
    }
}

/**
 * Some re-exports for convenience
 */
export {
    WebkitMessagingConfig,
    WebkitMessagingTransport,
    WindowsMessagingConfig,
    WindowsMessagingTransport,
    WindowsInteropMethods,
    NotificationMessage,
    RequestMessage,
    Subscription,
    MessageResponse,
    MessageError,
    SubscriptionEvent,
    WindowsNotification,
    WindowsRequestMessage,
    AndroidMessagingConfig,
    AndroidMessagingTransport,
    createTypedMessages,
};
