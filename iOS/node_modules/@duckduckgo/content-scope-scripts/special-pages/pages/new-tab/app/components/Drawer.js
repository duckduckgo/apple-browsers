import { useRef, useId, useLayoutEffect, useEffect } from 'preact/hooks';
import { batch, useComputed, useSignal } from '@preact/signals';
import { useEnv } from '../../../../shared/components/EnvironmentProvider.js';
import { useMessaging } from '../types.js';

const CLOSE_DRAWER_EVENT = 'close-drawer';
const TOGGLE_DRAWER_EVENT = 'toggle-drawer';
const OPEN_DRAWER_EVENT = 'open-drawer';

/**
 * @typedef {'hidden' | 'visible'} DrawerVisibility
 */

/**
 * Hook that manages the state and behavior of a drawer component.
 *
 * There are three main considerations here:
 *  - 1: we make the API available with events (via `useDrawerControls`)
 *  - 2: we use signals to trigger animations for performance (to prevent VDOM diffing)
 *  - 3: we provide a way for child components to render AFTER animations have ended, again for performance.
 * @param {DrawerVisibility} initial
 * @return {{
 *     buttonRef: import("preact").RefObject<HTMLButtonElement>,
 *     asideRef: import("preact").RefObject<HTMLDivElement>,
 *     visibility: import("@preact/signals").Signal<DrawerVisibility>,
 *     buttonId: string,
 *     drawerId: string,
 *     hidden: import("@preact/signals").Signal<boolean>,
 *     animating: import("@preact/signals").Signal<boolean>,
 *     displayChildren: import("@preact/signals").Signal<boolean>,
 * }}
 */
export function useDrawer(initial) {
    const { isReducedMotion } = useEnv();
    const asideRef = useRef(/** @type {HTMLDivElement|null} */ (null));
    const buttonRef = useRef(/** @type {HTMLButtonElement|null} */ (null));

    // id's for accessibility
    const buttonId = useId();
    const drawerId = useId();

    // the immediate value
    const visibility = useSignal(/** @type {DrawerVisibility} */ ('hidden'));

    // The value that determines if it's safe to render children
    // This takes animations into account, which is why is can't be a regular-derived state
    const displayChildren = useSignal(false);
    const animating = useSignal(false);

    // Derive a 'hidden' signal that can be used as an aria-hidden={hidden}
    // it needs to be done this way to `.value` being accessed in the top level of the application
    const hidden = useComputed(() => displayChildren.value === false);

    // react to the global API events
    useLayoutEffect(() => {
        const controller = new AbortController();
        const aside = asideRef.current;
        if (!aside) return;

        /**
         * @param {DrawerVisibility} value
         */
        const update = (value) => {
            visibility.value = value;
            if (isReducedMotion) {
                displayChildren.value = visibility.value === 'visible';
            }
        };

        // Event handlers
        const close = () => update('hidden');
        const open = () => update('visible');
        const toggle = () => {
            const next = visibility.value === 'hidden' ? 'visible' : 'hidden';
            update(next);
        };

        // the 3 methods that can be triggered from anywhere in the app
        window.addEventListener(CLOSE_DRAWER_EVENT, close, { signal: controller.signal });
        window.addEventListener(TOGGLE_DRAWER_EVENT, toggle, { signal: controller.signal });
        window.addEventListener(OPEN_DRAWER_EVENT, open, { signal: controller.signal });

        // update `displayChildren` when animations complete.
        aside?.addEventListener(
            'transitionend',
            (e) => {
                // ignore child animations
                if (e.target !== e.currentTarget) return;
                batch(() => {
                    displayChildren.value = visibility.value === 'visible';
                    animating.value = false;

                    // move focus back to the button when the drawer is closed
                    // this needs to be done otherwise it's a violation of aria rules
                    if (displayChildren.value === false) {
                        buttonRef.current?.focus?.();
                    }
                });
            },
            { signal: controller.signal },
        );

        // set animating = true when a parent transition starts
        aside?.addEventListener(
            'transitionstart',
            (e) => {
                // ignore child animations
                if (e.target !== e.currentTarget) return;
                batch(() => {
                    animating.value = true;
                    displayChildren.value = true;
                });
            },
            { signal: controller.signal },
        );

        return () => {
            controller.abort();
        };
    }, [isReducedMotion, initial]);

    const ntp = useMessaging();

    /**
     * Open initially if required too
     */
    useEffect(() => {
        if (initial === 'visible') {
            _open();
        }
        return ntp.messaging.subscribe('customizer_autoOpen', () => {
            _open();
        });
    }, [initial, ntp]);

    return {
        buttonRef,
        visibility,
        displayChildren,
        buttonId,
        drawerId,
        hidden,
        animating,
        asideRef,
    };
}

function _toggle() {
    window.dispatchEvent(new CustomEvent(TOGGLE_DRAWER_EVENT));
}

function _open() {
    window.dispatchEvent(new CustomEvent(OPEN_DRAWER_EVENT));
}

function _close() {
    window.dispatchEvent(new CustomEvent(CLOSE_DRAWER_EVENT));
}

/**
 * familiar React-style API
 */
export function useDrawerControls() {
    return {
        toggle: _toggle,
        close: _close,
        open: _open,
    };
}
