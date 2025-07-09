import { Messaging, MessagingContext, WebkitMessagingConfig } from '../../index.js';

/**
 * Configuration for WebkitMessaging
 */
const config = new WebkitMessagingConfig({
    hasModernWebkitAPI: true,
    secret: 'SECRET',
    webkitMessageHandlerNames: ['contentScopeScripts'],
});

/**
 * Context for messaging - this helps native platforms differentiate between senders
 */
const messagingContext = new MessagingContext({
    context: 'contentScopeScripts',
    featureName: 'hello-world',
    env: 'development',
});

/**
 * With config + context, now create an instance:
 */
const messaging = new Messaging(messagingContext, config);

/**
 * send notifications (fire and forget)
 */
messaging.notify('sendPixel');

/**
 * request data
 */
(async () => {
    const result = await messaging.request('helloWorld', { foo: 'bar' });
    console.log(result);
})();
