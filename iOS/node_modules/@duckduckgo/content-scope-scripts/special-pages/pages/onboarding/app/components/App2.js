import { h } from 'preact';
import { useContext } from 'preact/hooks';
import { GlobalContext, GlobalDispatch } from '../global';
import { useEnv } from '../../../../shared/components/EnvironmentProvider';
import { usePlatformName } from './SettingsProvider';
import { ErrorBoundary } from '../../../../shared/components/ErrorBoundary';
import { Fallback } from '../pages/Fallback';
import { Background } from './v3/Background.js';
import { BeforeAfterProvider } from './v3/BeforeAfterProvider';
import { SingleStep } from './v3/SingleStep';
import { Hiker } from './v3/Hiker';

import styles from './App2.module.css';

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function App2({ children }) {
    const { debugState } = useEnv();
    const platformName = usePlatformName();
    const globalState = useContext(GlobalContext);
    const dispatch = useContext(GlobalDispatch);

    const { activeStep, activeStepVisible, exiting, step } = globalState;

    const advance = () => dispatch({ kind: 'advance' });

    const didCatch = ({ error }) => {
        const message = error?.message || 'unknown';
        dispatch({ kind: 'error-boundary', error: { message, id: activeStep } });
    };

    // typescript is not quite smart enough to figure this part out

    // for screens that animate out, trigger the 'advance' when it's finished.
    function animationDidFinish(e) {
        if (e.target?.dataset?.exiting === 'true') {
            advance();
        }
    }

    // otherwise, for none-animating steps, just advance immediately when 'exiting' is set
    const didRender = (e) => {
        /** @type {import('../types').Step['id'][]} */
        const ignoredSteps = ['welcome', 'getStarted'];
        const shouldSkipAnimation = ignoredSteps.includes(e?.dataset?.current);
        if (shouldSkipAnimation && exiting === true) {
            advance();
        }
    };

    return (
        <main className={styles.main} data-platform-name={platformName || 'macos'} data-app-version="2">
            <Background />
            {debugState && <Debug state={globalState} />}
            <div
                className={styles.container}
                data-current={activeStep}
                data-exiting={String(exiting)}
                data-step-visible={activeStepVisible}
                ref={didRender}
                onAnimationEnd={animationDidFinish}
            >
                <ErrorBoundary didCatch={didCatch} fallback={<Fallback />}>
                    <BeforeAfterProvider>
                        <SingleStep />
                    </BeforeAfterProvider>
                </ErrorBoundary>
            </div>
            {(step.id === 'welcome' || step.id === 'getStarted') && <Hiker />}
            {children}
        </main>
    );
}

function Debug(props) {
    const { order, step, exiting, activeStep, nextStep } = props.state;
    const debugData = { order, step, exiting, activeStep, nextStep };

    return (
        <div style={{ position: 'absolute', top: 0, right: 0, overflowY: 'scroll', height: '100vh', zIndex: 10000 }}>
            <pre>
                <code>{JSON.stringify(debugData, null, 2)}</code>
            </pre>
        </div>
    );
}
