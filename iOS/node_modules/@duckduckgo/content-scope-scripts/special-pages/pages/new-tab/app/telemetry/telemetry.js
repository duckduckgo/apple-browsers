/**
 * @import { Messaging } from "@duckduckgo/messaging"
 */
export class Telemetry {
    static EVENT_REQUEST = 'TELEMETRY_EVENT_REQUEST';
    static EVENT_RESPONSE = 'TELEMETRY_EVENT_RESPONSE';
    static EVENT_SUBSCRIPTION = 'TELEMETRY_EVENT_SUBSCRIPTION';
    static EVENT_SUBSCRIPTION_DATA = 'TELEMETRY_EVENT_SUBSCRIPTION_DATA';
    static EVENT_NOTIFICATION = 'TELEMETRY_EVENT_NOTIFICATION';
    static EVENT_BROADCAST = 'TELEMETRY_*';

    eventTarget = new EventTarget();
    /** @type {any[]} */
    eventStore = [];
    storeEnabled = false;

    /**
     * @param now
     */
    constructor(now = Date.now()) {
        this.now = now;
        performance.mark('ddg-telemetry-init');
        this._setupMessagingMarkers();
    }

    _setupMessagingMarkers() {
        this.eventTarget.addEventListener(Telemetry.EVENT_REQUEST, (/** @type {CustomEvent<any>} */ { detail }) => {
            const named = `ddg request ${detail.method} ${detail.timestamp}`;
            performance.mark(named);
            this.broadcast(detail);
        });
        this.eventTarget.addEventListener(Telemetry.EVENT_RESPONSE, (/** @type {CustomEvent<any>} */ { detail }) => {
            const reqNamed = `ddg request ${detail.method} ${detail.timestamp}`;
            const resNamed = `ddg response ${detail.method} ${detail.timestamp}`;
            performance.mark(resNamed);
            performance.measure(reqNamed, reqNamed, resNamed);
            this.broadcast(detail);
        });
        this.eventTarget.addEventListener(Telemetry.EVENT_SUBSCRIPTION, (/** @type {CustomEvent<any>} */ { detail }) => {
            const named = `ddg subscription ${detail.method} ${detail.timestamp}`;
            performance.mark(named);
            this.broadcast(detail);
        });
        this.eventTarget.addEventListener(Telemetry.EVENT_SUBSCRIPTION_DATA, (/** @type {CustomEvent<any>} */ { detail }) => {
            const named = `ddg subscription data ${detail.method} ${detail.timestamp}`;
            performance.mark(named);
            this.broadcast(detail);
        });
        this.eventTarget.addEventListener(Telemetry.EVENT_NOTIFICATION, (/** @type {CustomEvent<any>} */ { detail }) => {
            const named = `ddg notification ${detail.method} ${detail.timestamp}`;
            performance.mark(named);
            this.broadcast(detail);
        });
    }

    broadcast(payload) {
        if (this.eventStore.length >= 50) {
            this.eventStore = [];
        }
        if (this.storeEnabled) {
            this.eventStore.push(structuredClone(payload));
        }
        this.eventTarget.dispatchEvent(new CustomEvent(Telemetry.EVENT_BROADCAST, { detail: payload }));
    }

    measureFromPageLoad(marker, measure = 'measure__' + Date.now()) {
        if (!performance.getEntriesByName(marker).length) {
            performance.mark(marker);
            performance.measure(measure, 'ddg-telemetry-init', marker);
        }
    }
}

/**
 * @implements Messaging
 */
class MessagingObserver {
    /** @type {Map<string, number>} */
    observed = new Map();

    /**
     * @param {import("@duckduckgo/messaging").Messaging} messaging
     * @param {EventTarget} eventTarget
     */
    constructor(messaging, eventTarget) {
        this.messaging = messaging;
        this.messagingContext = messaging.messagingContext;
        this.transport = messaging.transport;
        this.eventTarget = eventTarget;
    }

    /**
     * @param {string} method
     * @param {Record<string, any>} params
     */
    request(method, params) {
        const timestamp = Date.now();
        const json = {
            kind: 'request',
            method,
            params,
            timestamp,
        };
        this.record(Telemetry.EVENT_REQUEST, json);
        return (
            this.messaging
                .request(method, params)
                // eslint-disable-next-line promise/prefer-await-to-then
                .then((x) => {
                    const resJson = {
                        kind: 'response',
                        method,
                        result: x,
                        timestamp,
                    };
                    this.record(Telemetry.EVENT_RESPONSE, resJson);
                    return x;
                })
        );
    }

    /**
     * @param {string} method
     * @param {Record<string, any>} params
     */
    notify(method, params) {
        const json = {
            kind: 'notification',
            method,
            params,
        };
        this.record(Telemetry.EVENT_NOTIFICATION, json);
        return this.messaging.notify(method, params);
    }

    /**
     * @param method
     * @param callback
     * @return {function(): void}
     */
    subscribe(method, callback) {
        const timestamp = Date.now();
        const json = {
            kind: 'subscription',
            method,
            timestamp,
        };

        this.record(Telemetry.EVENT_SUBSCRIPTION, json);
        return this.messaging.subscribe(method, (params) => {
            const json = {
                kind: 'subscription data',
                method,
                timestamp,
                params,
            };
            this.record(Telemetry.EVENT_SUBSCRIPTION_DATA, json);
            callback(params);
        });
    }

    /**
     * @param {string} name
     * @param {Record<string, any>} detail
     */
    record(name, detail) {
        this.eventTarget.dispatchEvent(new CustomEvent(name, { detail }));
    }
}

/**
 * @param {Messaging} messaging
 * @return {{telemetry: Telemetry, messaging: MessagingObserver}}
 */
export function install(messaging) {
    const telemetry = new Telemetry();
    const observedMessaging = new MessagingObserver(messaging, telemetry.eventTarget);
    return { telemetry, messaging: observedMessaging };
}
