import { useEffect, useRef } from 'preact/hooks';

const REGISTER_EVENT = 'register-dropzone';
const CLEAR_EVENT = 'clear-dropzone';

/**
 * Setup the global listeners for the page. This prevents a new tab
 * being launched when an unsupported link is dropped in (like from another app)
 */
export function useGlobalDropzone() {
    useEffect(() => {
        /** @type {HTMLElement[]} */
        let safezones = [];
        const controller = new AbortController();

        /**
         * Allow HTML elements to be part of a 'safe zone' where dropping is allowed
         */
        window.addEventListener(
            REGISTER_EVENT,
            (/** @type {CustomEvent} */ e) => {
                if (isValidEvent(e)) {
                    safezones.push(e.detail.dropzone);
                }
            },
            { signal: controller.signal },
        );

        /**
         * Allow registered HTML elements to be removed from the list of safe-zones
         */
        window.addEventListener(
            CLEAR_EVENT,
            (/** @type {CustomEvent} */ e) => {
                if (isValidEvent(e)) {
                    const match = safezones.findIndex((x) => x === e.detail.dropzone);
                    safezones.splice(match, 1);
                }
            },
            { signal: controller.signal },
        );

        /**
         * Use drag over to ensure
         */
        document.addEventListener(
            'dragover',
            (event) => {
                if (!event.target) return;
                const target = /** @type {HTMLElement} */ (event.target);
                if (safezones.length > 0) {
                    for (const safezone of safezones) {
                        if (safezone.contains(target)) return;
                    }
                }

                // At the moment, this is not supported in the Playwright tests :(
                // So we allow the integration build to check first
                let preventDrop = true;
                // eslint-disable-next-line no-labels,no-unused-labels
                $INTEGRATION: (() => {
                    if (window.__playwright_01) {
                        preventDrop = false;
                    }
                })();

                if (preventDrop) {
                    // if we get here, we're stopping a drag/drop from being allowed
                    event.preventDefault();
                    if (event.dataTransfer) {
                        event.dataTransfer.dropEffect = 'none';
                    }
                }
            },
            { signal: controller.signal },
        );
        return () => {
            controller.abort();
            safezones = [];
        };
    }, []);
}

/**
 * Register an area allowed to receive drop events
 */
export function useDropzoneSafeArea() {
    const ref = useRef(null);
    useEffect(() => {
        if (!ref.current) return;
        const evt = new CustomEvent(REGISTER_EVENT, { detail: { dropzone: ref.current } });
        window.dispatchEvent(evt);
        return () => {
            window.dispatchEvent(new CustomEvent(CLEAR_EVENT, { detail: { dropzone: ref.current } }));
        };
    }, []);
    return ref;
}

/**
 * @param {Record<string, any>} input
 * @return {input is {dropzone: HTMLElement}}
 */
function isValidEvent(input) {
    return 'detail' in input && input.detail.dropzone instanceof HTMLElement;
}
