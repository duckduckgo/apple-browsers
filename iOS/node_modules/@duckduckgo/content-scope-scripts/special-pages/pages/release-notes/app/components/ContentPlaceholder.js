/**
 * Renders a purely visual placeholder for when content is still loading.
 * Sematic HTML tags are used to mimic the final rendered elements.
 */
import { h } from 'preact';
import styles from './ContentPlaceholder.module.css';

export function ContentPlaceholder() {
    return (
        <div className={styles.contentPlaceholder} aria-hidden="true" data-testid="placeholder">
            <h2></h2>
            <p></p>
            <ul>
                <li>
                    <p></p>
                    <p></p>
                </li>
                <li>
                    <p></p>
                    <p></p>
                </li>
            </ul>
        </div>
    );
}
