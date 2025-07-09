import { Messaging } from '@duckduckgo/messaging';
import ContentFeature from '../content-feature';
import {
    InstallProxy,
    DidInstall,
    ProxyNotification,
    ProxyRequest,
    ProxyResponse,
    SubscriptionRequest,
    SubscriptionResponse,
    SubscriptionUnsubscribe,
} from './message-bridge/schema.js';
import * as capturedGlobals from '../captured-globals.js';
import { isBeingFramed } from '../utils.js';

/**
 * @typedef {Pick<import("../captured-globals.js"),
 *    "dispatchEvent" | "addEventListener" | "CustomEvent">
 * } Captured
 */

/**
 * This part has access to messaging handlers
 */
export class MessageBridge extends ContentFeature {
    /** @type {Captured} */
    captured = capturedGlobals;
    /**
     * A mapping of feature names to instances of `Messaging`.
     * This allows the bridge to handle more than 1 feature at a time.
     * @type {Map<string, Messaging>}
     */
    proxies = new capturedGlobals.Map();

    /**
     * If any subscriptions are created, we store the cleanup functions
     * for later use.
     * @type {Map<string, () => void>}
     */
    subscriptions = new capturedGlobals.Map();

    /**
     * This side of the bridge can only be instantiated once,
     * so we use this flag to ensure we can handle multiple invocations
     */
    installed = false;

    init(args) {
        /**
         * This feature never operates in a frame or insecure context
         */
        if (isBeingFramed() || !isSecureContext) return;
        /**
         * This feature never operates without messageSecret
         */
        if (!args.messageSecret) return;

        const { captured } = this;

        /**
         * @param {string} eventName
         * @return {`${string}-${string}`}
         */
        function appendToken(eventName) {
            return `${eventName}-${args.messageSecret}`;
        }

        /**
         * @param {{name: string; id: string} & Record<string, any>} incoming
         */
        const reply = (incoming) => {
            if (!args.messageSecret) return this.log('ignoring because args.messageSecret was absent');
            const eventName = appendToken(incoming.name + '-' + incoming.id);
            const event = new captured.CustomEvent(eventName, { detail: incoming });
            captured.dispatchEvent(event);
        };

        /**
         * @template T
         * @param {{ create: (params: any) => T | null, NAME: string }} ClassType - A class with a `create` static method.
         * @param {(instance: T) => void} callback - A callback that receives an instance of the class.
         */
        const accept = (ClassType, callback) => {
            captured.addEventListener(appendToken(ClassType.NAME), (/** @type {CustomEvent<unknown>} */ e) => {
                this.log(`${ClassType.NAME}`, JSON.stringify(e.detail));
                const instance = ClassType.create(e.detail);
                if (instance) {
                    callback(instance);
                } else {
                    this.log('Failed to create an instance');
                }
            });
        };

        /**
         * These are all the messages we accept from the page-world.
         */
        this.log(`bridge is installing...`);
        accept(InstallProxy, (install) => {
            this.installProxyFor(install, args.messagingConfig, reply);
        });
        accept(ProxyNotification, (notification) => this.proxyNotification(notification));
        accept(ProxyRequest, (request) => this.proxyRequest(request, reply));
        accept(SubscriptionRequest, (subscription) => this.proxySubscription(subscription, reply));
        accept(SubscriptionUnsubscribe, (unsubscribe) => this.removeSubscription(unsubscribe.id));
    }

    /**
     * Installing a feature proxy is the act of creating a fresh instance of 'Messaging', but
     * using the same underlying transport
     *
     * @param {InstallProxy} install
     * @param {import('@duckduckgo/messaging').MessagingConfig} config
     * @param {(payload: {name: string; id: string} & Record<string, any>) => void} reply
     */
    installProxyFor(install, config, reply) {
        const { id, featureName } = install;
        if (this.proxies.has(featureName)) return this.log('ignoring `installProxyFor` because it exists', featureName);
        const allowed = this.getFeatureSettingEnabled(featureName);
        if (!allowed) {
            return this.log('not installing proxy, because', featureName, 'was not enabled');
        }

        const ctx = { ...this.messaging.messagingContext, featureName };
        const messaging = new Messaging(ctx, config);
        this.proxies.set(featureName, messaging);

        this.log('did install proxy for ', featureName);
        reply(new DidInstall({ id }));
    }

    /**
     * @param {ProxyRequest} request
     * @param {(payload: {name: string; id: string} & Record<string, any>) => void} reply
     */
    async proxyRequest(request, reply) {
        const { id, featureName, method, params } = request;

        const proxy = this.proxies.get(featureName);
        if (!proxy) return this.log('proxy was not installed for ', featureName);

        this.log('will proxy', request);

        try {
            const result = await proxy.request(method, params);
            const responseEvent = new ProxyResponse({
                method,
                featureName,
                result,
                id,
            });
            reply(responseEvent);
        } catch (e) {
            const errorResponseEvent = new ProxyResponse({
                method,
                featureName,
                error: { message: e.message },
                id,
            });
            reply(errorResponseEvent);
        }
    }

    /**
     * @param {SubscriptionRequest} subscription
     * @param {(payload: {name: string; id: string} & Record<string, any>) => void} reply
     */
    proxySubscription(subscription, reply) {
        const { id, featureName, subscriptionName } = subscription;
        const proxy = this.proxies.get(subscription.featureName);
        if (!proxy) return this.log('proxy was not installed for', featureName);

        this.log('will setup subscription', subscription);

        // cleanup existing subscriptions first
        const prev = this.subscriptions.get(id);
        if (prev) {
            this.removeSubscription(id);
        }

        const unsubscribe = proxy.subscribe(subscriptionName, (/** @type {Record<string, any>} */ data) => {
            const responseEvent = new SubscriptionResponse({
                subscriptionName,
                featureName,
                params: data,
                id,
            });
            reply(responseEvent);
        });

        this.subscriptions.set(id, unsubscribe);
    }

    /**
     * @param {string} id
     */
    removeSubscription(id) {
        const unsubscribe = this.subscriptions.get(id);
        this.log(`will remove subscription`, id);
        unsubscribe?.();
        this.subscriptions.delete(id);
    }

    /**
     * @param {ProxyNotification} notification
     */
    proxyNotification(notification) {
        const proxy = this.proxies.get(notification.featureName);
        if (!proxy) return this.log('proxy was not installed for', notification.featureName);

        this.log('will proxy notification', notification);
        proxy.notify(notification.method, notification.params);
    }

    /**
     * @param {Parameters<console['log']>} args
     */
    log(...args) {
        if (this.isDebug) {
            console.log('[isolated]', ...args);
        }
    }

    load(_args) {}
}

export default MessageBridge;
