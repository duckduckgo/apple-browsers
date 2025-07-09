import { h } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { useEnv } from '../../../../shared/components/EnvironmentProvider';
import { ErrorBoundary } from '../../../../shared/components/ErrorBoundary';
import { useMessaging } from '../providers/MessagingProvider';
import { useErrorData } from '../providers/SpecialErrorProvider';
import { useTypedTranslation } from '../types';
import { AdvancedInfo } from './AdvancedInfo';
import styles from './App.module.css';
import { ErrorFallback } from './ErrorFallback';
import { Warning } from './Warning';

export function SpecialErrorView() {
    const [advancedInfoVisible, setAdvancedInfoVisible] = useState(false);
    const { messaging } = useMessaging();

    const advancedButtonHandler = () => {
        messaging?.advancedInfo();
        setAdvancedInfoVisible(true);
    };

    return (
        <div className={styles.container}>
            <Warning advancedInfoVisible={advancedInfoVisible} advancedButtonHandler={advancedButtonHandler} />
            {advancedInfoVisible && <AdvancedInfo />}
        </div>
    );
}

function PageTitle() {
    const { kind } = useErrorData();
    const { t } = useTypedTranslation();

    useEffect(() => {
        switch (kind) {
            case 'malware':
            case 'phishing':
            case 'scam':
                document.title = t('maliciousSiteTabTitle');
                break;
            default:
                document.title = t('sslPageHeading');
        }
    }, [kind, t]);

    return null;
}

export function App() {
    const { messaging } = useMessaging();
    const { isDarkMode } = useEnv();

    /**
     * @param {Error} error
     */
    function didCatch(error) {
        const message = error?.message || 'unknown';
        console.error('ErrorBoundary', message);
        messaging?.reportPageException({ message });
    }

    return (
        <main className={styles.main} data-theme={isDarkMode ? 'dark' : 'light'}>
            <PageTitle />
            <ErrorBoundary didCatch={({ error }) => didCatch(error)} fallback={<ErrorFallback />}>
                <SpecialErrorView />
                <WillThrow />
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
