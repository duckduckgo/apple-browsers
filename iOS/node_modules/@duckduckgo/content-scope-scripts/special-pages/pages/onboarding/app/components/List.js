import { h } from 'preact';
import cn from 'classnames';
import styles from './List.module.css';
import { useEffect, useRef } from 'preact/hooks';
import { useAutoAnimate } from '@formkit/auto-animate/preact';
import { useEnv } from '../../../../shared/components/EnvironmentProvider';

/**
 * List component is used to display an item in a styled
 * @param {Object} props - The properties for the List component.
 * @param {import("preact").ComponentChild} props.children - List children
 * @param {boolean} [props.animate=false] - Should immediate children be animated into place?
 */
export function List({ animate = false, children }) {
    const { isReducedMotion } = useEnv();
    const [parent] = useAutoAnimate(isReducedMotion ? { duration: 0 } : undefined);

    return (
        <ul className={styles.list} ref={animate ? parent : null}>
            {children}
        </ul>
    );
}

/**
 * Plain list component is used to display an item in a list with minimal styling
 * @param {Object} props - The properties for the PlainList component.
 * @param {'default'|'bordered'} [props.variant='default'] - Whether to show a border between list items
 * @param {boolean} [props.animate=false] - Should immediate children be animated into place?
 * @param {import("preact").ComponentChild} props.children - List children
 */
export function PlainList({ variant, animate = false, children }) {
    const listRef = useRef(null);
    const containerRef = useRef(null);

    const classes = cn({
        [styles.plainList]: true,
        [styles.borderedList]: variant === 'bordered',
    });

    useEffect(() => {
        if (containerRef.current && listRef.current) {
            const container = /** @type {HTMLElement} */ (containerRef.current);
            const list = /** @type {HTMLElement} */ (listRef.current);

            container.style.height = `${list.clientHeight}px`;
        }
    }, [containerRef, listRef, children]);

    return (
        <div className={styles.plainListContainer} ref={animate ? containerRef : null}>
            <ul className={classes} ref={animate ? listRef : null}>
                {children}
            </ul>
        </div>
    );
}

/**
 * SummaryList component is used to display an item in a list.
 * @param {Object} props - The properties for the SymmaryList component.
 * @param {import("preact").ComponentChild} props.children - List children
 */
export function SummaryList(props) {
    return <ul className={styles.summaryList}>{props.children}</ul>;
}
