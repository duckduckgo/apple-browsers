import { h } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { DuckDuckGoLogo } from '../../../../shared/components/DuckDuckGoLogo/DuckDuckGoLogo';
import { useEnv } from '../../../../shared/components/EnvironmentProvider';
import { ErrorBoundary } from '../../../../shared/components/ErrorBoundary';
import { useMessaging } from '../index';
import styles from './App.module.css';
import { ErrorFallback } from './ErrorFallback';
import { ReleaseNotes } from './ReleaseNotes';

/**
 * @typedef {import('../../types/release-notes.js').UpdateMessage} UpdateMessage
 */

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} [props.children]
 */
export function App({ children }) {
    const { messages } = useMessaging();
    const { isDarkMode } = useEnv();
    /** @type {ReturnType<typeof useState<UpdateMessage>>} */
    const [releaseData, setReleaseData] = useState();

    useEffect(() => {
        return messages?.onUpdate((data) => {
            console.log('DATA RECEIVED', data);
            setReleaseData(data);
        });
    }, []);

    /**
     * @param {Error} error
     */
    function didCatch(error) {
        const message = error?.message || 'unknown';
        console.error('ErrorBoundary', message);
        messages?.reportPageException({ message });
    }
    return (
        <main className={styles.main} data-theme={isDarkMode ? 'dark' : 'light'}>
            <ErrorBoundary didCatch={({ error }) => didCatch(error)} fallback={<ErrorFallback />}>
                <header className={styles.header}>
                    <DuckDuckGoLogo />
                </header>
                <div class={styles.core}>{releaseData && <ReleaseNotes releaseData={releaseData} />}</div>
                <WillThrow />
                {children}
            </ErrorBoundary>
        </main>
    );
}

export function WillThrow() {
    const env = useEnv();
    if (env.willThrow) {
        throw new Error('Simulated Exception');
    }
    return null;
}
