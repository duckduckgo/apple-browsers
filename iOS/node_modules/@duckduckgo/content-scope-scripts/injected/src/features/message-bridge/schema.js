import { isObject, isString } from '../../type-utils.js';

/**
 * @import { Messaging } from "@duckduckgo/messaging";
 * @typedef {Pick<Messaging, 'notify' | 'request' | 'subscribe'>} MessagingInterface
 */

/**
 * Sending this event
 */
export class InstallProxy {
    static NAME = 'INSTALL_BRIDGE';
    get name() {
        return InstallProxy.NAME;
    }

    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.id
     */
    constructor(params) {
        this.featureName = params.featureName;
        this.id = params.id;
    }

    /**
     * @param {unknown} params
     */
    static create(params) {
        if (!isObject(params)) return null;
        if (!isString(params.featureName)) return null;
        if (!isString(params.id)) return null;
        return new InstallProxy({ featureName: params.featureName, id: params.id });
    }
}

export class DidInstall {
    static NAME = 'DID_INSTALL';
    get name() {
        return DidInstall.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.id
     */
    constructor(params) {
        this.id = params.id;
    }

    /**
     * @param {unknown} params
     */
    static create(params) {
        if (!isObject(params)) return null;
        if (!isString(params.id)) return null;
        return new DidInstall({ id: params.id });
    }
}

export class ProxyRequest {
    static NAME = 'PROXY_REQUEST';
    get name() {
        return ProxyRequest.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.method
     * @param {string} params.id
     * @param {Record<string, any>} [params.params]
     */
    constructor(params) {
        this.featureName = params.featureName;
        this.method = params.method;
        this.params = params.params;
        this.id = params.id;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
        if (!isObject(params)) return null;
        if (!isString(params.featureName)) return null;
        if (!isString(params.method)) return null;
        if (!isString(params.id)) return null;
        if (params.params && !isObject(params.params)) return null;
        return new ProxyRequest({
            featureName: params.featureName,
            method: params.method,
            params: params.params,
            id: params.id,
        });
    }
}

export class ProxyResponse {
    static NAME = 'PROXY_RESPONSE';
    get name() {
        return ProxyResponse.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.method
     * @param {string} params.id
     * @param {Record<string, any>} [params.result]
     * @param {import("@duckduckgo/messaging").MessageError} [params.error]
     */
    constructor(params) {
        this.featureName = params.featureName;
        this.method = params.method;
        this.result = params.result;
        this.error = params.error;
        this.id = params.id;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
        if (!isObject(params)) return null;
        if (!isString(params.featureName)) return null;
        if (!isString(params.method)) return null;
        if (!isString(params.id)) return null;
        if (params.result && !isObject(params.result)) return null;
        if (params.error && !isObject(params.error)) return null;
        return new ProxyResponse({
            featureName: params.featureName,
            method: params.method,
            result: params.result,
            error: params.error,
            id: params.id,
        });
    }
}

/**
 */
export class ProxyNotification {
    static NAME = 'PROXY_NOTIFICATION';
    get name() {
        return ProxyNotification.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.method
     * @param {Record<string, any>} [params.params]
     */
    constructor(params) {
        this.featureName = params.featureName;
        this.method = params.method;
        this.params = params.params;
    }

    /**
     * @param {unknown} params
     */
    static create(params) {
        if (!isObject(params)) return null;
        if (!isString(params.featureName)) return null;
        if (!isString(params.method)) return null;
        if (params.params && !isObject(params.params)) return null;
        return new ProxyNotification({
            featureName: params.featureName,
            method: params.method,
            params: params.params,
        });
    }
}

export class SubscriptionRequest {
    static NAME = 'SUBSCRIPTION_REQUEST';
    get name() {
        return SubscriptionRequest.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.subscriptionName
     * @param {string} params.id
     */
    constructor(params) {
        this.featureName = params.featureName;
        this.subscriptionName = params.subscriptionName;
        this.id = params.id;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
        if (!isObject(params)) return null;
        if (!isString(params.featureName)) return null;
        if (!isString(params.subscriptionName)) return null;
        if (!isString(params.id)) return null;
        return new SubscriptionRequest({
            featureName: params.featureName,
            subscriptionName: params.subscriptionName,
            id: params.id,
        });
    }
}

export class SubscriptionResponse {
    static NAME = 'SUBSCRIPTION_RESPONSE';
    get name() {
        return SubscriptionResponse.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.subscriptionName
     * @param {string} params.id
     * @param {Record<string, any>} [params.params]
     */
    constructor(params) {
        this.featureName = params.featureName;
        this.subscriptionName = params.subscriptionName;
        this.id = params.id;
        this.params = params.params;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
        if (!isObject(params)) return null;
        if (!isString(params.featureName)) return null;
        if (!isString(params.subscriptionName)) return null;
        if (!isString(params.id)) return null;
        if (params.params && !isObject(params.params)) return null;
        return new SubscriptionResponse({
            featureName: params.featureName,
            subscriptionName: params.subscriptionName,
            params: params.params,
            id: params.id,
        });
    }
}

export class SubscriptionUnsubscribe {
    static NAME = 'SUBSCRIPTION_UNSUBSCRIBE';
    get name() {
        return SubscriptionUnsubscribe.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.id
     */
    constructor(params) {
        this.id = params.id;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
        if (!isObject(params)) return null;
        if (!isString(params.id)) return null;
        return new SubscriptionUnsubscribe({
            id: params.id,
        });
    }
}
