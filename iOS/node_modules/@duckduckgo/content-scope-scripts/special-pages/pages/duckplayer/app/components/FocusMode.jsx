import { h } from 'preact';
import cn from 'classnames';
import { useCallback, useEffect } from 'preact/hooks';
import styles from './FocusMode.module.css';

const EVENT_ON = 'ddg-duckplayer-focusmode-on';
const EVENT_OFF = 'ddg-duckplayer-focusmode-off';

export function FocusMode() {
    useEffect(() => {
        let enabled = true;
        let timerId;
        const on = () => {
            if (document.documentElement.dataset.focusModeState === 'paused') {
                // try again after delay
                wait();
            } else {
                if (!enabled) {
                    return console.warn('ignoring focusMode because it was disabled');
                }
                document.documentElement.dataset.focusMode = 'on';
            }
        };
        const off = () => (document.documentElement.dataset.focusMode = 'off');
        const cancel = () => {
            clearTimeout(timerId);
            off();
            wait();
        };
        const wait = () => {
            clearTimeout(timerId);
            timerId = setTimeout(on, 2000);
        };

        // start
        wait();

        // event listeners on the top document
        document.addEventListener('mousemove', cancel);
        document.addEventListener('pointerdown', cancel);

        // other events that might occur
        window.addEventListener('frame-mousemove', cancel);
        window.addEventListener(EVENT_OFF, () => {
            enabled = false;
            off();
        });
        window.addEventListener(EVENT_ON, () => {
            if (enabled === true) return;
            enabled = true;
            on();
        });
        return () => {
            clearTimeout(timerId);
        };
    }, []);
    return null;
}

FocusMode.disable = () => setTimeout(() => window.dispatchEvent(new Event(EVENT_OFF)), 0);
FocusMode.enable = () => setTimeout(() => window.dispatchEvent(new Event(EVENT_ON)), 0);

/**
 * Hides the content in focus mode.
 *
 * @param {Object} props - The input props.
 * @param {import("preact").ComponentChild} props.children - The content to be hidden.
 * @param {"fade" | "slide"} [props.style="fade"] - The style for hiding the content.
 */
export function HideInFocusMode({ children, style = 'fade' }) {
    const classes = cn({
        [styles.hideInFocus]: true,
        [styles.fade]: style === 'fade',
        [styles.slide]: style === 'slide',
    });
    return (
        <div class={classes} data-style={style}>
            {children}
        </div>
    );
}

/**
 * Allow a mechanism for pausing focus mode - for example, when a tooltip is open
 */
export function useSetFocusMode() {
    return useCallback((/** @type {'enabled' | 'disabled' | 'paused'} */ action) => {
        document.documentElement.dataset.focusModeState = action;
    }, []);
}
