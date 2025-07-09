import { useContext } from 'preact/hooks';
import { OmnibarContext } from './OmnibarProvider.js';
import { h } from 'preact';
import { Omnibar } from './Omnibar.js';

/**
 * @typedef {import('../../../types/new-tab.js').OmnibarConfig} OmnibarConfig
 */

/**
 * Use this when you want to render the UI from a context where
 * the service is available.
 *
 * for example:
 *
 * ```jsx
 * <OmnibarProvider>
 *   <OmnibarConsumer />
 * </OmnibarProvider>
 * ```
 */
export function OmnibarConsumer() {
    const { state } = useContext(OmnibarContext);
    if (state.status === 'ready') {
        return <OmnibarReadyState config={state.config} />;
    }
    return null;
}

/**
 * @param {object} props
 * @param {OmnibarConfig} props.config
 */
function OmnibarReadyState({ config }) {
    const { setMode } = useContext(OmnibarContext);
    return <Omnibar mode={config.mode} setMode={setMode} enableAi={config.enableAi ?? true} />;
}
