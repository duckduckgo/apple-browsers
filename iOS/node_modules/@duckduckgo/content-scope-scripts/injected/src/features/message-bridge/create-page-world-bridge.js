import * as capturedGlobals from '../../captured-globals.js';
import {
    DidInstall,
    InstallProxy,
    ProxyNotification,
    ProxyRequest,
    ProxyResponse,
    SubscriptionRequest,
    SubscriptionResponse,
    SubscriptionUnsubscribe,
} from './schema.js';
import { isBeingFramed } from '../../utils.js';

/**
 * @import { MessagingInterface } from "./schema.js"
 * @typedef {Pick<import("../../captured-globals.js"),
 *    "dispatchEvent" | "addEventListener" | "removeEventListener" | "CustomEvent" | "String" | "Error" | "randomUUID">
 * } Captured
 */
/** @type {Captured} */
const captured = capturedGlobals;

export const ERROR_MSG = 'Did not install Message Bridge';

/**
 * Try to create a message bridge.
 *
 * Note: This will throw an exception if the bridge cannot be established.
 *
 * @param {string} featureName
 * @param {string} [token]
 * @return {MessagingInterface}
 * @throws {Error}
 */
export function createPageWorldBridge(featureName, token) {
    /**
     * This feature never operates without a featureName or token
     */
    if (typeof featureName !== 'string' || !token) {
        throw new captured.Error(ERROR_MSG);
    }
    /**
     * This feature never operates in a frame or insecure context
     */
    if (isBeingFramed() || !isSecureContext) {
        throw new captured.Error(ERROR_MSG);
    }

    /**
     * @param {string} eventName
     * @return {`${string}-${string}`}
     */
    const appendToken = (eventName) => {
        return `${eventName}-${token}`;
    };

    /**
     * Create the sender to centralize the sending logic
     * @param {{name: string} & Record<string, any>} incoming
     */
    const send = (incoming) => {
        // when the token is absent, just silently fail
        if (!token) return;
        const event = new captured.CustomEvent(appendToken(incoming.name), { detail: incoming });
        captured.dispatchEvent(event);
    };

    /**
     * Events are synchronous (even across contexts), so we can figure out
     * the result of installing the proxy before we return and give a
     * better experience for consumers
     */
    let installed = false;
    const id = random();
    const evt = new InstallProxy({ featureName, id });
    const evtName = appendToken(DidInstall.NAME + '-' + id);
    const didInstall = (/** @type {CustomEvent<unknown>} */ e) => {
        const result = DidInstall.create(e.detail);
        if (result && result.id === id) {
            installed = true;
        }
        captured.removeEventListener(evtName, didInstall);
    };

    captured.addEventListener(evtName, didInstall);
    send(evt);

    if (!installed) {
        // leaving this as a generic message for now
        throw new captured.Error(ERROR_MSG);
    }

    return createMessagingInterface(featureName, send, appendToken);
}

/**
 * We are executing exclusively in secure contexts, so this should never fail
 */
function random() {
    if (typeof captured.randomUUID !== 'function') throw new Error('unreachable');
    return captured.randomUUID();
}

/**
 * @param {string} featureName
 * @param {(evt: {name: string} & Record<string, any>) => void} send
 * @param {(s: string) => string} appendToken
 * @returns {MessagingInterface}
 */
function createMessagingInterface(featureName, send, appendToken) {
    return {
        /**
         * @param {string} method
         * @param {Record<string, any>} params
         */
        notify(method, params) {
            send(
                new ProxyNotification({
                    method,
                    params,
                    featureName,
                }),
            );
        },

        /**
         * @param {string} method
         * @param {Record<string, any>} params
         * @returns {Promise<any>}
         */
        request(method, params) {
            const id = random();

            send(
                new ProxyRequest({
                    method,
                    params,
                    featureName,
                    id,
                }),
            );

            return new Promise((resolve, reject) => {
                const responseName = appendToken(ProxyResponse.NAME + '-' + id);
                const handler = (/** @type {CustomEvent<unknown>} */ e) => {
                    const response = ProxyResponse.create(e.detail);
                    if (response && response.id === id) {
                        if ('error' in response && response.error) {
                            reject(new Error(response.error.message));
                        } else if ('result' in response) {
                            resolve(response.result);
                        }
                        captured.removeEventListener(responseName, handler);
                    }
                };
                captured.addEventListener(responseName, handler);
            });
        },

        /**
         * @param {string} name
         * @param {(d: any) => void} callback
         * @returns {() => void}
         */
        subscribe(name, callback) {
            const id = random();

            send(
                new SubscriptionRequest({
                    subscriptionName: name,
                    featureName,
                    id,
                }),
            );

            const handler = (/** @type {CustomEvent<unknown>} */ e) => {
                const subscriptionEvent = SubscriptionResponse.create(e.detail);
                if (subscriptionEvent) {
                    const { id: eventId, params } = subscriptionEvent;
                    if (eventId === id) {
                        callback(params);
                    }
                }
            };

            const type = appendToken(SubscriptionResponse.NAME + '-' + id);
            captured.addEventListener(type, handler);

            return () => {
                captured.removeEventListener(type, handler);
                const evt = new SubscriptionUnsubscribe({ id });
                send(evt);
            };
        },
    };
}
