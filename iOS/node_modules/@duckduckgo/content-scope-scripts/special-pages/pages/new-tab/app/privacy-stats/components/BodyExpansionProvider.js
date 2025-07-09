import { createContext, h } from 'preact';
import { useContext, useMemo, useState } from 'preact/hooks';
import { useMessaging } from '../../types.js';

/**
 * These are the API methods exposed
 */
export const BodyExpansionApiContext = createContext({
    showMore() {},
    showLess() {},
});

/**
 * This is the single value exposed
 */
export const BodyExpansionContext = createContext(/** @type {import('../../../types/new-tab').Expansion} */ ('collapsed'));

/**
 * Helper to access the value
 */
export function useBodyExpansion() {
    return useContext(BodyExpansionContext);
}

/**
 * Helper to access the API
 */
export function useBodyExpansionApi() {
    return useContext(BodyExpansionApiContext);
}

export function BodyExpanderProvider(props) {
    const messaging = useMessaging();
    const [bodyExpansion, setBodyExpansion] = useState(/** @type {import('../../../types/new-tab').Expansion} */ ('collapsed'));

    const bodyExpansionApi = useMemo(() => {
        return {
            showMore() {
                messaging.statsShowMore();
                setBodyExpansion('expanded');
            },
            showLess() {
                messaging.statsShowLess();
                setBodyExpansion('collapsed');
            },
        };
    }, [messaging]);

    return (
        <BodyExpansionApiContext.Provider value={bodyExpansionApi}>
            <BodyExpansionContext.Provider value={bodyExpansion}>{props.children}</BodyExpansionContext.Provider>
        </BodyExpansionApiContext.Provider>
    );
}
