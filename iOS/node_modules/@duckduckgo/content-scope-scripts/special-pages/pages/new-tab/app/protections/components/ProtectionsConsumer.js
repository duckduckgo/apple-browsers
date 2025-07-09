import { useContext } from 'preact/hooks';
import { ProtectionsContext, useBlockedCount } from './ProtectionsProvider.js';
import { h } from 'preact';
import { Protections } from './Protections.js';
import { ActivityProvider } from '../../activity/ActivityProvider.js';
import { ActivityConsumer } from '../../activity/components/Activity.js';
import { PrivacyStatsProvider } from '../../privacy-stats/components/PrivacyStatsProvider.js';
import { BodyExpanderProvider } from '../../privacy-stats/components/BodyExpansionProvider.js';
import { PrivacyStatsConsumer } from '../../privacy-stats/components/PrivacyStatsConsumer.js';

/**
 * @import {ProtectionsData, ProtectionsConfig} from '../../../types/new-tab.js';
 */

/**
 * Use this when you want to render the UI from a context where
 * the service is available.
 *
 * for example:
 *
 * ```jsx
 * <ProtectionsProvider>
 *   <ProtectionsConsumer />
 * </ProtectionsProvider>
 * ```
 */
export function ProtectionsConsumer() {
    const { state } = useContext(ProtectionsContext);
    if (state.status === 'ready') {
        return <ProtectionsReadyState data={state.data} config={state.config} />;
    }
    return null;
}

/**
 * @param {object} props
 * @param {ProtectionsData} props.data
 * @param {ProtectionsConfig} props.config
 */
function ProtectionsReadyState({ data, config }) {
    const { toggle, setFeed } = useContext(ProtectionsContext);
    const blockedCountSignal = useBlockedCount(data.totalCount);
    return (
        <Protections
            blockedCountSignal={blockedCountSignal}
            expansion={config.expansion}
            toggle={toggle}
            feed={config.feed}
            setFeed={setFeed}
        >
            {config.feed === 'activity' && (
                <ActivityProvider>
                    <ActivityConsumer showBurnAnimation={config.showBurnAnimation ?? true} />
                </ActivityProvider>
            )}
            {config.feed === 'privacy-stats' && (
                <PrivacyStatsProvider>
                    <BodyExpanderProvider>
                        <PrivacyStatsConsumer />
                    </BodyExpanderProvider>
                </PrivacyStatsProvider>
            )}
        </Protections>
    );
}
