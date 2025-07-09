import { WindowsMessagingConfig } from '../windows.js';
import { Messaging, MessagingContext } from '../../index.js';

/**
 * These 3 required methods that get assigned by the Native side.
 */
// @ts-expect-error - webview is not in @types/chrome
const windowsInteropPostMessage = window.chrome.webview.postMessage;
// @ts-expect-error - webview is not in @types/chrome
const windowsInteropAddEventListener = window.chrome.webview.addEventListener;
// @ts-expect-error - webview is not in @types/chrome
const windowsInteropRemoveEventListener = window.chrome.webview.removeEventListener;

/**
 * With those methods available in the same lexical scope, we can then create
 * our WindowsMessagingConfig
 */
const config = new WindowsMessagingConfig({
    methods: {
        postMessage: windowsInteropPostMessage,
        addEventListener: windowsInteropAddEventListener,
        removeEventListener: windowsInteropRemoveEventListener,
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
