import { h } from 'preact';
import styles from './Switch.module.css';

/**
 * Switch component used to toggle between two states.
 *
 * @param {Object} props - The props object.
 * @param {string} props.ariaLabel - Label applied to the <input />
 * @param {"macos" | "windows"} props.platformName - only supported platforms
 * @param {"light" | "dark"} props.theme
 * @param {boolean} props.pending - Indicates if the switch is in a pending state.
 * @param {boolean} [props.checked=false] - Indicates if the switch is checked.
 * @param {'small' | 'medium' | 'large'} [props.size] - Which size?
 * @param {Function} props.onChecked - Callback function to be called when the switch is checked.
 * @param {Function} props.onUnchecked - Callback function to be called when the switch is unchecked.
 */
export function Switch({ checked = false, platformName, size, theme, ...props }) {
    const { onChecked, onUnchecked, ariaLabel, pending } = props;
    function change(e) {
        if (e.target.checked === true) {
            onChecked();
        } else {
            onUnchecked();
        }
    }
    return (
        <label class={styles.label} data-platform-name={platformName} data-theme={theme} data-size={size}>
            <input
                disabled={pending}
                type="checkbox"
                role="switch"
                aria-label={ariaLabel}
                class={styles.input}
                checked={checked}
                onChange={change}
            />
            <span class={styles.switch} style="transition-duration: 130ms;transition-delay: 0ms;"></span>
        </label>
    );
}
