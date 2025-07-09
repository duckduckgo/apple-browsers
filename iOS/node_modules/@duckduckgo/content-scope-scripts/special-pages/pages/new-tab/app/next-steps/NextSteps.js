import { h } from 'preact';
import { NextStepsContext, NextStepsProvider } from './NextStepsProvider.js';
import { useContext } from 'preact/hooks';
import { NextStepsCardGroup } from './components/NextStepsGroup.js';

/**
 * Use this when rendered within a widget list.
 *
 * It reaches out to access this widget's global visibility, and chooses
 * whether to incur the side effects (data fetching).
 */
export function NextStepsCustomized() {
    return (
        <NextStepsProvider>
            <NextStepsConsumer />
        </NextStepsProvider>
    );
}

/**
 * Use this when you want to render the UI from a context where
 * the service is available.
 *
 * for example:
 *
 * ```jsx
 * <PrivacyStatsProvider>
 *     <PrivacyStatsConsumer />
 * </PrivacyStatsProvider>
 * ```
 */
export function NextStepsConsumer() {
    const { state, toggle } = useContext(NextStepsContext);
    if (state.status === 'ready' && state.data.content) {
        const ids = state.data.content.map((x) => x.id);
        const { action, dismiss } = useContext(NextStepsContext);
        return <NextStepsCardGroup types={ids} toggle={toggle} expansion={state.config.expansion} action={action} dismiss={dismiss} />;
    }
    return null;
}
