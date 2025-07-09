import { legacySendMessage } from './utils.js';
import { TestTransportConfig } from '../../messaging/index.js';

/**
 * Workaround defining MessagingTransport locally because "import()" is not working in `@implements`
 * @typedef {import('@duckduckgo/messaging').MessagingTransport} MessagingTransport
 */

/**
 * @deprecated - A temporary constructor for the extension to make the messaging config
 */
export function extensionConstructMessagingConfig() {
    const messagingTransport = new SendMessageMessagingTransport();
    return new TestTransportConfig(messagingTransport);
}

/**
 * A temporary implementation of {@link MessagingTransport} to communicate with Extensions.
 * It wraps the current messaging system that calls `sendMessage`
 *
 * @implements {MessagingTransport}
 * @deprecated - Use this only to communicate with Android and the Extension while support to {@link Messaging}
 * is not ready and we need to use `sendMessage()`.
 */
export class SendMessageMessagingTransport {
    /**
     * Queue of callbacks to be called with messages sent from the Platform.
     * This is used to connect requests with responses and to trigger subscriptions callbacks.
     */
    _queue = new Set();

    constructor() {
        this.globals = {
            window: globalThis,
            globalThis,
            JSONparse: globalThis.JSON.parse,
            JSONstringify: globalThis.JSON.stringify,
            Promise: globalThis.Promise,
            Error: globalThis.Error,
            String: globalThis.String,
        };
    }

    /**
     * Callback for update() handler. This connects messages sent from the Platform
     * with callback functions in the _queue.
     * @param {any} response
     */
    onResponse(response) {
        this._queue.forEach((subscription) => subscription(response));
    }

    /**
     * @param {import('@duckduckgo/messaging').NotificationMessage} msg
     */
    notify(msg) {
        let params = msg.params;

        // Unwrap 'setYoutubePreviewsEnabled' params to match expected payload
        // for sendMessage()
        if (msg.method === 'setYoutubePreviewsEnabled') {
            params = msg.params?.youtubePreviewsEnabled;
        }
        // Unwrap 'updateYouTubeCTLAddedFlag' params to match expected payload
        // for sendMessage()
        if (msg.method === 'updateYouTubeCTLAddedFlag') {
            params = msg.params?.youTubeCTLAddedFlag;
        }

        legacySendMessage(msg.method, params);
    }

    /**
     * @param {import('@duckduckgo/messaging').RequestMessage} req
     * @return {Promise<any>}
     */
    request(req) {
        let comparator = (eventData) => {
            return eventData.responseMessageType === req.method;
        };
        let params = req.params;

        // Adapts request for 'getYouTubeVideoDetails' by identifying the correct
        // response for each request and updating params to expect current
        // implementation specifications.
        if (req.method === 'getYouTubeVideoDetails') {
            comparator = (eventData) => {
                return (
                    eventData.responseMessageType === req.method &&
                    eventData.response &&
                    eventData.response.videoURL === req.params?.videoURL
                );
            };
            params = req.params?.videoURL;
        }

        legacySendMessage(req.method, params);

        return new this.globals.Promise((resolve) => {
            this._subscribe(comparator, (msgRes, unsubscribe) => {
                unsubscribe();

                return resolve(msgRes.response);
            });
        });
    }

    /**
     * @param {import('@duckduckgo/messaging').Subscription} msg
     * @param {(value: unknown | undefined) => void} callback
     */
    subscribe(msg, callback) {
        const comparator = (eventData) => {
            return eventData.messageType === msg.subscriptionName || eventData.responseMessageType === msg.subscriptionName;
        };

        // only forward the 'params' ('response' in current format), to match expected
        // callback from a SubscriptionEvent
        const cb = (eventData) => {
            return callback(eventData.response);
        };
        return this._subscribe(comparator, cb);
    }

    /**
     * @param {(eventData: any) => boolean} comparator
     * @param {(value: any, unsubscribe: (()=>void)) => void} callback
     * @internal
     */
    _subscribe(comparator, callback) {
        /** @type {(()=>void) | undefined} */
        // eslint-disable-next-line prefer-const
        let teardown;

        /**
         * @param {MessageEvent} event
         */
        const idHandler = (event) => {
            if (!event) {
                console.warn('no message available');
                return;
            }
            if (comparator(event)) {
                if (!teardown) throw new this.globals.Error('unreachable');
                callback(event, teardown);
            }
        };
        this._queue.add(idHandler);

        teardown = () => {
            this._queue.delete(idHandler);
        };

        return () => {
            teardown?.();
        };
    }
}
