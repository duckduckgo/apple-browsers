import { Component } from 'preact';

/**
 * @typedef {{
 *   fallback: import("preact").ComponentChild,
 *   didCatch: (params: {error: Error; message: string, info: any}) => void,
 *   context?: string;
 * }} Props
 *
 * @extends {Component<Props, { hasError: boolean }>}
 */
export class ErrorBoundary extends Component {
    constructor(props) {
        super(props);
        this.state = { hasError: false };
    }

    static getDerivedStateFromError() {
        // Update state so the next render will show the fallback UI.
        return { hasError: true };
    }

    componentDidCatch(error, info) {
        console.error(error);
        console.log(info);

        let message = error.message;
        if (typeof message !== 'string') message = 'unknown';

        // prettier-ignore
        const composed = this.props.context
            ? [this.props.context, message].join(' ')
            : message;

        this.props.didCatch({ error, message: composed, info });
    }

    render() {
        if (this.state.hasError) {
            // You can render any custom fallback UI
            return this.props.fallback;
        }

        return this.props.children;
    }
}
