import { h } from 'preact';
import styles from './Header.module.css';
import { Delay } from './Timeout';

/**
 * Renders a header component.
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children - The content to display on the side of the header.
 * @param {import("preact").ComponentChild} [props.aside=null] - The content to display on the side of the header.
 */
export function Header({ children, aside = null }) {
    return (
        <header className={styles.header}>
            <div className={styles.logo}>
                <img className={styles.svg} src="assets/img/dax.svg" alt="DuckDuckGo Logo" />
            </div>

            <div className={styles.titleContainer}>
                <h1 className={styles.title}>
                    <Delay ms={300}>{children}</Delay>
                </h1>
            </div>
            {aside && <div className={styles.aside}>{aside}</div>}
        </header>
    );
}
