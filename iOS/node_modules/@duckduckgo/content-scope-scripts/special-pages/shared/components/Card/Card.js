import { h } from 'preact';
import classNames from 'classnames';
import styles from './Card.module.css';

/**
 * @param {object} props
 * @param {string} [props.className]
 * @param {import("preact").ComponentChild} [props.children]
 */
export function Card({ className, children }) {
    return <section className={classNames(styles.card, className)}>{children}</section>;
}
