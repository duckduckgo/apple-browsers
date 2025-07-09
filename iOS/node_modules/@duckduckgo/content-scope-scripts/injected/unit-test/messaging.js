import {
    Messaging,
    MessagingContext,
    TestTransportConfig,
    RequestMessage,
    NotificationMessage,
    Subscription,
    MessageResponse,
    SubscriptionEvent,
} from '@duckduckgo/messaging';
import { AndroidMessagingConfig } from '@duckduckgo/messaging/lib/android.js';

describe('Messaging Transports', () => {
    it('calls transport with a RequestMessage', () => {
        const { messaging, transport } = createMessaging();

        const spy = spyOn(transport, 'request');

        messaging.request('helloWorld', { foo: 'bar' });

        // grab the auto-generated `id` field
        const [requestMessage] = spy.calls.first()?.args ?? [];
        expect(typeof requestMessage.id).toBe('string');
        expect(requestMessage.id.length).toBeGreaterThan(0);

        expect(spy).toHaveBeenCalledWith(
            new RequestMessage({
                context: 'contentScopeScripts',
                featureName: 'hello-world',
                id: requestMessage.id,
                method: 'helloWorld',
                params: { foo: 'bar' },
            }),
        );
    });
    it('calls transport with a NotificationMessage', () => {
        const { messaging, transport } = createMessaging();

        const spy = spyOn(transport, 'notify');

        messaging.notify('helloWorld', { foo: 'bar' });

        expect(spy).toHaveBeenCalledWith(
            new NotificationMessage({
                context: 'contentScopeScripts',
                featureName: 'hello-world',
                method: 'helloWorld',
                params: { foo: 'bar' },
            }),
        );
    });
    it('calls transport with a Subscription', () => {
        const { messaging, transport } = createMessaging();

        const spy = spyOn(transport, 'subscribe');
        const callback = jasmine.createSpy();

        messaging.subscribe('helloWorld', callback);

        expect(spy).toHaveBeenCalledWith(
            new Subscription({
                context: 'contentScopeScripts',
                featureName: 'hello-world',
                subscriptionName: 'helloWorld',
            }),
            callback,
        );
    });
});

describe('Android', () => {
    /**
     * @param {Record<string, any>} target
     * @return {AndroidMessagingConfig}
     */
    function createConfig(target) {
        const config = new AndroidMessagingConfig({
            target,
            messageSecret: 'abc',
            javascriptInterface: 'AnyRandomValue',
            messageCallback: 'callback_abc_def',
            debug: false,
        });
        return config;
    }
    /**
     * @param {string} featureName
     * @param {AndroidMessagingConfig} config
     */
    function createContext(featureName, config) {
        const messageContextA = new MessagingContext({
            context: 'contentScopeScripts',
            featureName,
            env: 'development',
        });
        const messaging = new Messaging(messageContextA, config);
        return { messaging };
    }
    it('sends notification to 1 feature', () => {
        const spy = jasmine.createSpy();
        const target = {
            AnyRandomValue: {
                process: spy,
            },
        };
        const config = createConfig(target);
        const { messaging } = createContext('featureA', config);
        messaging.notify('helloWorld');
        const payload = '{"context":"contentScopeScripts","featureName":"featureA","method":"helloWorld","params":{}}';
        const secret = 'abc';
        expect(spy).toHaveBeenCalledWith(payload, secret);
    });
    it('sends notification to 2 separate features', () => {
        const spy = jasmine.createSpy();
        const target = {
            AnyRandomValue: {
                process: spy,
            },
        };
        const config = createConfig(target);
        const { messaging } = createContext('featureA', config);
        const { messaging: bMessaging } = createContext('featureB', config);
        messaging.notify('helloWorld');
        bMessaging.notify('helloWorld');
        const expected1 = '{"context":"contentScopeScripts","featureName":"featureA","method":"helloWorld","params":{}}';
        const expected2 = '{"context":"contentScopeScripts","featureName":"featureA","method":"helloWorld","params":{}}';
        expect(spy).toHaveBeenCalledTimes(2);
        expect(spy).toHaveBeenCalledWith(expected1, 'abc');
        expect(spy).toHaveBeenCalledWith(expected2, 'abc');
    });
    it('sends request and gets response', async () => {
        const spy = jasmine.createSpy();
        /** @type {MessageResponse} */
        let msg;
        /** @type {string} */
        let token;
        const target = {
            AnyRandomValue: {
                process: (outgoing, _token) => {
                    msg = JSON.parse(outgoing);
                    token = _token;
                    spy(outgoing, _token);
                },
            },
        };
        const config = createConfig(target);
        const { messaging } = createContext('featureA', config);
        const request = messaging.request('helloWorld');

        // @ts-expect-error - unit-testing
        if (!msg) throw new Error('must have set msg by this point in the test');

        // simulate a valid response
        const response = new MessageResponse({
            id: msg.id,
            context: 'contentScopeScripts',
            featureName: msg.featureName,
            result: { foo: 'bar' },
        });

        // pretend to call back from native
        target[config.messageCallback](config.messageSecret, response);

        // wait for it to resolve
        const result = await request;

        const outgoingMessage = {
            context: 'contentScopeScripts',
            featureName: 'featureA',
            method: 'helloWorld',
            id: msg.id,
            params: {},
        };

        // Android messages are sent as a JSON string
        const asJsonString = JSON.stringify(outgoingMessage);
        expect(spy).toHaveBeenCalledWith(asJsonString, 'abc');

        // ensure the result is correct
        expect(result).toEqual({ foo: 'bar' });

        // @ts-expect-error - unit-testing
        expect(token).toEqual(config.messageSecret);
    });
    it('allows subscriptions', (done) => {
        const spy = jasmine.createSpy();
        const globalTarget = {
            AnyRandomValue: {
                process: spy,
            },
        };
        const config = createConfig(globalTarget);
        const { messaging } = createContext('featureA', config);

        // create the message as the native side would
        const subEvent1 = new SubscriptionEvent({
            context: 'contentScopeScripts',
            featureName: 'featureA',
            subscriptionName: 'onUpdate',
            params: { foo: 'bar' },
        });

        // subscribe to 'onUpdate'
        messaging.subscribe('onUpdate', (data) => {
            expect(data).toEqual(subEvent1.params);
            done();
        });

        // simulate native calling this method
        globalTarget[config.messageCallback](config.messageSecret, subEvent1);
    });
});

/**
 * Creates a test transport and Messaging instance for testing
 */
function createMessaging() {
    /** @type {import("@duckduckgo/messaging").MessagingTransport} */
    const transport = {
        notify(_) {
            // test
        },

        request: (_msg) => {
            // test
            return Promise.resolve(null);
        },

        subscribe(_msg) {
            // test
            return () => {
                // test teardown
            };
        },
    };

    const testTransportConfig = new TestTransportConfig(transport);

    const messagingContext = new MessagingContext({
        context: 'contentScopeScripts',
        featureName: 'hello-world',
        env: 'development',
    });

    const messaging = new Messaging(messagingContext, testTransportConfig);

    return { transport, messaging };
}
