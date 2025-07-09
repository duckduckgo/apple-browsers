import styles from './Progress.module.css';
import { h } from 'preact';
import cn from 'classnames';

/**
 * Renders a progress component indicating the current progress
 *
 * @param {Object} props - The props object
 * @param {number} props.total - The total value of the progress
 * @param {number} props.current - The current value of the progress
 */
export function Progress({ total, current }) {
    return (
        <div className={styles.progressContainer}>
            <div className={styles.count}>
                {current} / {total}
            </div>
            <progress className={styles.progress} max={total} value={current}>
                (Page {current} of circa {total})
            </progress>
        </div>
    );
}

export function SingleLineProgress({ total, current }) {
    return (
        <div className={cn([styles.progressContainer, styles.singleLineContainer])}>
            <div className={styles.count}>
                {current} / {total}
            </div>
            <progress className={styles.progress} max={total} value={current}>
                (Page {current} of circa {total})
            </progress>
        </div>
    );
}
