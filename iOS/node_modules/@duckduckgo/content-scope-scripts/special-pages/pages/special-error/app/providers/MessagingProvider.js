import { createContext, h } from 'preact';
import { useContext } from 'preact/hooks';

export const MessagingContext = createContext({
    messaging: /** @type {import('../../src/index.js').SpecialErrorPage | null} */ (null),
});

/**
 * Provide messaging for the application.
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children
 * @param {import('../../src/index.js').SpecialErrorPage | null} props.messaging
 */
export function MessagingProvider({ children, messaging }) {
    return <MessagingContext.Provider value={{ messaging }}>{children}</MessagingContext.Provider>;
}

export function useMessaging() {
    return useContext(MessagingContext);
}
