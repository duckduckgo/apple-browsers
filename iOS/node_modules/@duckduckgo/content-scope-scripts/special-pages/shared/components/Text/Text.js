import { h } from 'preact';
import classNames from 'classnames';
import styles from './Text.module.css';

/**
 * @param {object} props
 * @param {import('preact').JSX.ElementType} [props.as]
 * @param {Omit<keyof styles, "text">} [props.variant]
 * @param {string} [props.className]
 * @param {boolean} [props.strictSpacing] - Apply Design System letter spacing. Default: true
 * @param {import("preact").ComponentChild} [props.children]
 */
// eslint-disable-next-line no-redeclare
export function Text({ as: Comp = 'p', variant, strictSpacing = true, className, children }) {
    return (
        <Comp className={classNames({ [styles[`${variant}`]]: variant, [styles.strictSpacing]: strictSpacing }, className)}>
            {children}
        </Comp>
    );
}
