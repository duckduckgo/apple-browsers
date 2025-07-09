/**
 * These are all the shared data types used throughout. Transports receive these types and
 * can choose how to deliver the message to their respective native platforms.
 *
 * - Notifications via {@link NotificationMessage}
 * - Request -> Response via {@link RequestMessage} and {@link MessageResponse}
 * - Subscriptions via {@link Subscription}
 *
 * Note: For backwards compatibility, some platforms may alter the data shape within the transport.
 *
 * @module Messaging Schema
 *
 */

/**
 * This is the format of an outgoing message.
 *
 * - See {@link MessageResponse} for what's expected in a response
 *
 * **NOTE**:
 * - Windows will alter this before it's sent, see: {@link Messaging.WindowsRequestMessage}
 */
export class RequestMessage {
    /**
     * @param {object} params
     * @param {string} params.context
     * @param {string} params.featureName
     * @param {string} params.method
     * @param {string} params.id
     * @param {Record<string, any>} [params.params]
     * @internal
     */
    constructor(params) {
        /**
         * The global context for this message. For example, something like `contentScopeScripts` or `specialPages`
         * @type {string}
         */
        this.context = params.context;
        /**
         * The name of the sub-feature, such as `duckPlayer` or `clickToLoad`
         * @type {string}
         */
        this.featureName = params.featureName;
        /**
         * The name of the handler to be executed on the native side
         */
        this.method = params.method;
        /**
         * The `id` that native sides can use when sending back a response
         */
        this.id = params.id;
        /**
         * Optional data payload - must be a plain key/value object
         */
        this.params = params.params;
    }
}

/**
 * Native platforms should deliver responses in this format
 */
export class MessageResponse {
    /**
     * @param {object} params
     * @param {string} params.context
     * @param {string} params.featureName
     * @param {string} params.id
     * @param {Record<string, any>} [params.result]
     * @param {MessageError} [params.error]
     * @internal
     */
    constructor(params) {
        /**
         * The global context for this message. For example, something like `contentScopeScripts` or `specialPages`
         * @type {string}
         */
        this.context = params.context;
        /**
         * The name of the sub-feature, such as `duckPlayer` or `clickToLoad`
         * @type {string}
         */
        this.featureName = params.featureName;
        /**
         * The resulting payload - must be a plain object
         */
        this.result = params.result;
        /**
         * The `id` that is used to pair this response with its sender
         */
        this.id = params.id;
        /**
         * An optional error
         */
        this.error = params.error;
    }
}

/**
 * **NOTE**:
 * - Windows will alter this before it's sent, see: {@link Messaging.WindowsNotification}
 */
export class NotificationMessage {
    /**
     * @param {object} params
     * @param {string} params.context
     * @param {string} params.featureName
     * @param {string} params.method
     * @param {Record<string, any>} [params.params]
     * @internal
     */
    constructor(params) {
        /**
         * The global context for this message. For example, something like `contentScopeScripts` or `specialPages`
         */
        this.context = params.context;
        /**
         * The name of the sub-feature, such as `duckPlayer` or `clickToLoad`
         */
        this.featureName = params.featureName;
        /**
         * The name of the handler to be executed on the native side
         */
        this.method = params.method;
        /**
         * An optional payload
         */
        this.params = params.params;
    }
}

export class Subscription {
    /**
     * @param {object} params
     * @param {string} params.context
     * @param {string} params.featureName
     * @param {string} params.subscriptionName
     * @internal
     */
    constructor(params) {
        this.context = params.context;
        this.featureName = params.featureName;
        this.subscriptionName = params.subscriptionName;
    }
}

/**
 * This is the shape of payloads that can be delivered via subscriptions
 */
export class SubscriptionEvent {
    /**
     * @param {object} params
     * @param {string} params.context
     * @param {string} params.featureName
     * @param {string} params.subscriptionName
     * @param {Record<string, any>} [params.params]
     * @internal
     */
    constructor(params) {
        this.context = params.context;
        this.featureName = params.featureName;
        this.subscriptionName = params.subscriptionName;
        this.params = params.params;
    }
}

/**
 * Optionally received as part of {@link MessageResponse}
 */
export class MessageError {
    /**
     * @param {object} params
     * @param {string} params.message
     * @internal
     */
    constructor(params) {
        this.message = params.message;
    }
}

/**
 * @param {RequestMessage} request
 * @param {Record<string, any>} data
 * @return {data is MessageResponse}
 */
export function isResponseFor(request, data) {
    if ('result' in data) {
        return data.featureName === request.featureName && data.context === request.context && data.id === request.id;
    }
    if ('error' in data) {
        if ('message' in data.error) {
            return true;
        }
    }
    return false;
}

/**
 * @param {Subscription} sub
 * @param {Record<string, any>} data
 * @return {data is SubscriptionEvent}
 */
export function isSubscriptionEventFor(sub, data) {
    if ('subscriptionName' in data) {
        return data.featureName === sub.featureName && data.context === sub.context && data.subscriptionName === sub.subscriptionName;
    }

    return false;
}
