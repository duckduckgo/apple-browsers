import { h } from 'preact';
import { ErrorBoundary } from '../../../shared/components/ErrorBoundary.js';
import { useMessaging } from './types.js';

export const INLINE_ERROR = 'A problem occurred with this feature. DuckDuckGo was notified';

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 * @param {(message: string) => string} [props.format] - This gives you access to the error message, so you can append relevant context
 * @param {string} [props.context] - Passed to `ErrorBoundary`, if you provide this, it will be prepended to messages. Favor this before
 * using `format`
 * @param {(message: string) => import("preact").ComponentChild} [props.fallback]
 */
export function InlineErrorBoundary({ children, format, context, fallback }) {
    const messaging = useMessaging();
    /**
     * @param {string} message
     */
    const didCatch = (message) => {
        const formatted = format?.(message) || message;
        messaging.reportPageException({ message: formatted });
    };
    const fallbackElement = fallback?.(INLINE_ERROR) || <p>{INLINE_ERROR}</p>;
    return (
        <ErrorBoundary context={context} didCatch={({ message }) => didCatch(message)} fallback={fallbackElement}>
            {children}
        </ErrorBoundary>
    );
}
