import { useContext } from 'preact/hooks';
import { PrivacyStatsContext } from './PrivacyStatsProvider.js';
import { h } from 'preact';
import { useBodyExpansion } from './BodyExpansionProvider.js';
import { PrivacyStats } from './PrivacyStats.js';

/**
 * Use this when you want to render the UI from a context where
 * the service is available.
 *
 * for example:
 *
 * ```jsx
 * <PrivacyStatsProvider>
 *     <BodyExpanderProvider>
 *        <PrivacyStatsConsumer />
 *     </BodyExpanderProvider
 * </PrivacyStatsProvider>
 * ```
 */
export function PrivacyStatsConsumer() {
    const { state } = useContext(PrivacyStatsContext);
    const secondaryExpansion = useBodyExpansion();
    if (state.status === 'ready') {
        return <PrivacyStats expansion={secondaryExpansion} trackerCompanies={state.data.trackerCompanies} />;
    }
    return null;
}
