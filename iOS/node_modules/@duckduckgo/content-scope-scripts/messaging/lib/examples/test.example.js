import { Messaging, MessagingContext, TestTransportConfig } from '../../index.js';

/**
 * Creates an ad-hoc messaging transport on the fly - useful for testing
 * You need to implement
 * - notify
 * - request
 * - subscribe
 */
const config = new TestTransportConfig({
    notify(msg) {
        console.log(msg);
    },
    request: (msg) => {
        if (msg.method === 'getUserValues') {
            return Promise.resolve({
                foo: 'bar',
            });
        }
        return Promise.resolve(null);
    },
    subscribe(msg) {
        console.log(msg);
        return () => {
            console.log('teardown');
        };
    },
});

const messagingContext = new MessagingContext({
    context: 'contentScopeScripts',
    featureName: 'hello-world',
    env: 'development',
});

/**
 * And then send notifications!
 */
const messaging = new Messaging(messagingContext, config);
messaging.notify('helloWorld');

/**
 * Or request some data
 */
messaging.request('getData', { foo: 'bar' }).then(console.log).catch(console.error);

/**
 * Or subscribe for push messages
 */
const unsubscribe = messaging.subscribe('getData', (data) => console.log(data));

// later
unsubscribe();
