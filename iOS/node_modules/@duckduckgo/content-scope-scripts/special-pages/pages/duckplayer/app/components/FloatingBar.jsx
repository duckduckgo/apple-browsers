import styles from './FloatingBar.module.css';
import { h } from 'preact';
import cn from 'classnames';

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 * @param {boolean} [props.inset]
 */
export function FloatingBar({ children, inset = false }) {
    return <div class={cn(styles.floatingBar, { [styles.inset]: inset })}>{children}</div>;
}

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function TopBar({ children }) {
    return <div class={styles.topBar}>{children}</div>;
}
