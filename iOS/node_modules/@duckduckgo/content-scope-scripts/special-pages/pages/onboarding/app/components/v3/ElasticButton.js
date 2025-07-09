import { h } from 'preact';
import cn from 'classnames';
import styles from './ElasticButton.module.css';

/**
 * @typedef {Object} ElasticButtonProps
 * @property {string} text - Button text
 * @property {'primary' | 'secondary'} [props.variant="primary"]
 * @property {import('preact').JSX.Element} [startIcon] - Optional leading icon
 * @property {import('preact').JSX.Element} [endIcon] - Optional trailing icon
 * @property {string} [longestText] - String that sets the maximum text width for the button
 * @property {boolean} [props.elastic=true] - Whether the button should grow on hover
 */

/**
 * Renders a button component with that grows on hover.
 *
 * @param {ElasticButtonProps & import("preact").ComponentProps<"button">} props
 */
export function ElasticButton({ text, variant = 'primary', startIcon, endIcon, longestText, elastic = true, ...rest }) {
    const classes = cn({
        [styles.button]: true,
        [styles.primary]: variant === 'primary',
        [styles.secondary]: variant === 'secondary',
        [styles.elastic]: elastic === true,
    });
    return (
        <button className={classes} aria-label={text} {...rest}>
            <div className={styles.background}></div>
            <div class={styles.content}>
                {startIcon}
                {longestText ? <FixedWidthContent text={text} longestText={longestText} /> : text}
                {endIcon}
            </div>
        </button>
    );
}

/**
 * Creates a block of text that has a constant width equal to the longest possible text
 *
 * @param {object} props
 * @param {string} props.text - Button text
 * @param {string} props.longestText - The longest text string the button can have
 */
export function FixedWidthContent({ text, longestText }) {
    return (
        <span className={styles.fixedWidthContainer}>
            <span aria-hidden={true} className={styles.hiddenContent}>
                {longestText}
            </span>
            <span className={styles.visibleContent}>{text}</span>
        </span>
    );
}
