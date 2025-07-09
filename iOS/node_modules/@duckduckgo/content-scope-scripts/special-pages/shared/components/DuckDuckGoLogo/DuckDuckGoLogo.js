import { h } from 'preact';
import classNames from 'classnames';
import styles from './DuckDuckGoLogo.module.css';

/**
 * Renders a header component.
 */
export function DuckDuckGoLogo() {
    return (
        <span className={styles.logo}>
            <span className={classNames(styles.logo, 'offscreen')}>DuckDuckGo</span>
        </span>
    );
}
