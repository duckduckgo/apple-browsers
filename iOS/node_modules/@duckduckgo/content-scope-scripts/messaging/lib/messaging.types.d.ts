interface UnstableWebkit {
    messageHandlers: Record<
        string,
        {
            postMessage?: (...args: unknown[]) => void;
        }
    >;
}

interface UnstableMockCall {
    payload: import('../index.js').RequestMessage | import('../index.js').NotificationMessage | import('../index.js').Subscription;
    response?: Record<string, unknown>;
}

interface Window {
    webkit: UnstableWebkit;
    windowsInteropPostMessage: Window['postMessage'];
    windowsInteropAddEventListener: Window['addEventListener'];
    windowsInteropRemoveEventListener: Window['removeEventListener'];
    __playwright_01: {
        mockResponses: Record<string, import('../index.js').MessageResponse>;
        subscriptionEvents: import('../index.js').SubscriptionEvent[];
        publishSubscriptionEvent?: (evt: import('../index.js').SubscriptionEvent) => void;
        mocks: {
            outgoing: UnstableMockCall[];
        };
    };
}

declare let windowsInteropPostMessage: unknown;
declare let windowsInteropAddEventListener: unknown;
declare let windowsInteropRemoveEventListener: unknown;
