import styles from './CustomizerDrawerInner.module.css';
import { Fragment, h } from 'preact';
import cn from 'classnames';

/**
 * @param {object} props
 * @param {import("preact").ComponentChild | null} props.title
 * @param {import("preact").ComponentChild} props.children
 */
export function CustomizerSection({ title, children }) {
    return (
        <div className={styles.section}>
            {title === null && children}
            {title !== null && (
                <Fragment>
                    <h3 className={styles.sectionTitle}>{title}</h3>
                    <div className={styles.sectionBody}>{children}</div>
                </Fragment>
            )}
        </div>
    );
}

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function BorderedSection({ children }) {
    return <div class={cn(styles.section, styles.borderedSection)}>{children}</div>;
}
