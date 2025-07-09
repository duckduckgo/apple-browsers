import { h } from 'preact';
import styles from './Fallback.module.css';

/**
 * @param {object} props
 * @param {boolean} props.showDetails
 * @param {import("preact").ComponentChild} [props.children]
 */
export function Fallback({ showDetails, children }) {
    return (
        <div class={styles.fallback}>
            <div>
                <p>Something went wrong!</p>
                {children}
                {showDetails && (
                    <p>
                        Please check logs for a message called <code>reportPageException</code>
                    </p>
                )}
            </div>
        </div>
    );
}
