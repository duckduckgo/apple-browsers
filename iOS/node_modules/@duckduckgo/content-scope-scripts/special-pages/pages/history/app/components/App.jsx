import { h } from 'preact';
import cn from 'classnames';
import styles from './App.module.css';
import { useEnv } from '../../../../shared/components/EnvironmentProvider.js';
import { Header } from './Header.js';
import { ResultsContainer } from './Results.js';
import { useEffect, useRef } from 'preact/hooks';
import { Sidebar } from './Sidebar.js';
import { useRowInteractions } from '../global/Providers/SelectionProvider.js';
import { useQueryContext } from '../global/Providers/QueryProvider.js';
import { useContextMenuForEntries } from '../global/hooks/useContextMenuForEntries.js';
import { useAuxClickHandler } from '../global/hooks/useAuxClickHandler.js';
import { useButtonClickHandler } from '../global/hooks/useButtonClickHandler.js';
import { useLinkClickHandler } from '../global/hooks/useLinkClickHandler.js';
import { useResetSelectionsOnQueryChange } from '../global/hooks/useResetSelectionsOnQueryChange.js';
import { useSearchCommitForRange } from '../global/hooks/useSearchCommitForRange.js';
import { useURLReflection } from '../global/hooks/useURLReflection.js';
import { useSearchCommit } from '../global/hooks/useSearchCommit.js';
import { useRangesData } from '../global/Providers/HistoryServiceProvider.js';
import { usePlatformName } from '../types.js';
import { useLayoutMode } from '../global/hooks/useLayoutMode.js';
import { useClickAnywhereElse } from '../global/hooks/useClickAnywhereElse.jsx';

export function App() {
    const platformName = usePlatformName();
    const mainRef = useRef(/** @type {HTMLElement|null} */ (null));
    const { isDarkMode } = useEnv();
    const ranges = useRangesData();
    const query = useQueryContext();
    const mode = useLayoutMode();

    /**
     * Handlers that are global in nature
     */
    useResetSelectionsOnQueryChange();
    useLinkClickHandler();
    useButtonClickHandler();
    useContextMenuForEntries();
    useAuxClickHandler();
    useURLReflection();
    useSearchCommit();
    useSearchCommitForRange();
    const clickAnywhere = useClickAnywhereElse();

    /**
     * onClick can be passed directly to the main container,
     * onKeyDown will be observed at the document level.
     * todo: can this be resolved if the `main` element is given focus/tab-index?
     */
    const { onClick, onKeyDown } = useRowInteractions(mainRef);

    useEffect(() => {
        // whenever the query changes, scroll the main container back to the top
        const unsubscribe = query.subscribe(() => {
            mainRef.current?.scrollTo(0, 0);
        });

        document.addEventListener('keydown', onKeyDown);

        return () => {
            document.removeEventListener('keydown', onKeyDown);
            unsubscribe();
        };
    }, [onKeyDown, query]);

    return (
        <div
            class={styles.layout}
            data-theme={isDarkMode ? 'dark' : 'light'}
            data-platform={platformName}
            data-layout-mode={mode}
            onClick={clickAnywhere}
        >
            <aside class={styles.aside}>
                <Sidebar ranges={ranges} />
            </aside>
            <header class={styles.header}>
                <Header />
            </header>
            <main class={cn(styles.main, styles.customScroller)} ref={mainRef} onClick={onClick}>
                <ResultsContainer />
            </main>
        </div>
    );
}

export function AppLevelErrorBoundaryFallback({ children }) {
    return (
        <div class={styles.paddedError}>
            <p>{children}</p>
            <div class={styles.paddedErrorRecovery}>
                You can try to{' '}
                <button
                    onClick={() => {
                        const current = new URL(window.location.href);
                        current.search = '';
                        current.pathname = '';
                        location.href = current.toString();
                    }}
                >
                    Reload this page
                </button>
            </div>
        </div>
    );
}
