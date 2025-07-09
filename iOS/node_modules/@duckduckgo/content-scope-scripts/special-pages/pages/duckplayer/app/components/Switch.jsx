import styles from './Switch.module.css';
import { h } from 'preact';
import cn from 'classnames';

/**
 * Renders a switch component with given checked, id and onChange props.
 *
 * @param {object} props - The component props.
 * @param {boolean} props.checked - Indicates whether the switch is checked or not.
 * @param {() => void} props.onChange - The callback function to be called when the switch is toggled.
 * @param {ImportMeta['platform']} props.platformName - The callback function to be called when the switch is toggled.
 * @param {string} props.id
 */
export function Switch({ checked, onChange, id, platformName = 'ios' }) {
    return (
        <button
            role="switch"
            aria-checked={checked}
            onClick={onChange}
            id={id}
            className={cn(styles.switch, {
                [styles.ios]: platformName === 'ios',
                [styles.android]: platformName === 'android',
            })}
        >
            <span className={styles.thumb}></span>
        </button>
    );
}
