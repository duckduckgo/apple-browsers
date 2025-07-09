import { h } from 'preact';
import styles from './Content.module.css';

export function Content({ children }) {
    return (
        <div className={styles.indent}>
            <div className={styles.wrapper}>{children}</div>
        </div>
    );
}
