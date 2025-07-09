import styles from './ShowHide.module.css';
import cn from 'classnames';
import { Chevron } from './Icons.js';
import { h } from 'preact';

/**
 * Function to handle showing or hiding content based on certain conditions.
 *
 * @param {Object} props - Input parameters for controlling the behavior of the ShowHide functionality.
 * @param {string} props.label
 * @param {() => void} props.onClick
 * @param {import("preact").ComponentProps<'button'>} [props.buttonAttrs]
 */
export function ShowHideButtonCircle({ label, onClick, buttonAttrs = {} }) {
    return (
        <button {...buttonAttrs} class={cn(styles.button, styles.round)} aria-label={label} data-toggle="true" onClick={onClick}>
            <div class={styles.iconBlock}>
                <Chevron />
            </div>
        </button>
    );
}

/**
 * Use this version for a small pill version with text and option aria-label
 * @param {object} props
 * @param {string} props.text
 * @param {string|undefined} props.label
 * @param {() => void} props.onClick
 * @param {boolean} [props.fill=true]
 * @param {import("preact").ComponentProps<'button'>} [props.buttonAttrs]
 */
export function ShowHideButtonPill({ label, onClick, text, fill = true, buttonAttrs = {} }) {
    // if a different label was given, make the main text aria-hidden=true
    const btnText = label ? <span aria-hidden="true">{text}</span> : text;

    return (
        <button
            {...buttonAttrs}
            aria-label={label}
            class={cn(styles.button, styles.hover, styles.pill, fill && styles.fill)}
            data-toggle="true"
            onClick={onClick}
        >
            <Chevron />
            {btnText}
        </button>
    );
}

/**
 * A container you can place a <ShowHideButtonPill /> into.
 * Consumers can use the `data-show-hide` to show/hide the bar
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function ShowHideBar({ children }) {
    return (
        <div class={styles.bar} data-show-hide>
            {children}
        </div>
    );
}
