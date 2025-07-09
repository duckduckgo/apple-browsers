import { FocusMode } from '../components/FocusMode.jsx';
import { h } from 'preact';

/**
 * @param {import("../settings.js").Settings} settings
 */
export function createAppFeaturesFrom(settings) {
    return {
        focusMode: () => {
            if (settings.focusMode.state === 'enabled') {
                return <FocusMode />;
            } else {
                return null;
            }
        },
    };
}
