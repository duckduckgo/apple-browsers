import { postDebugMessage } from '../utils.js';
import ContentFeature from '../content-feature.js';

export default class ExceptionHandler extends ContentFeature {
    init() {
        // Report to the debugger panel if an uncaught exception occurs
        const handleUncaughtException = (e) => {
            postDebugMessage(
                'jsException',
                {
                    documentUrl: document.location.href,
                    message: e.message,
                    filename: e.filename,
                    lineno: e.lineno,
                    colno: e.colno,
                    stack: e.error?.stack,
                },
                true,
            );
            this.addDebugFlag();
        };
        globalThis.addEventListener('error', handleUncaughtException);
    }
}
