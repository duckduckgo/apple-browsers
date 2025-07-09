import { useTypedTranslationWith } from '../../types.js';
import { useVisibility } from '../../widget-list/widget-config.provider.js';
import { useCustomizer } from '../../customizer/components/CustomizerMenu.js';
import { ProtectionsProvider } from './ProtectionsProvider.js';
import { h } from 'preact';

import { ProtectionsConsumer } from './ProtectionsConsumer.js';

/**
 * @import enStrings from "../strings.json"
 * @typedef {enStrings} Strings
 */

/**
 * Use this when rendered within a widget list.
 *
 * It reaches out to access this widget's global visibility, and chooses
 * whether to incur the side effects (data fetching).
 */
export function ProtectionsCustomized() {
    const { t } = useTypedTranslationWith(/** @type {Strings} */ ({}));

    /**
     * The menu title for the stats widget is changes when the menu is in the sidebar.
     */
    const sectionTitle = t('protections_menuTitle');

    const { visibility, id, toggle, index } = useVisibility();

    useCustomizer({ title: sectionTitle, id, icon: 'shield', toggle, visibility: visibility.value, index });

    if (visibility.value === 'hidden') {
        return null;
    }

    return (
        <ProtectionsProvider>
            <ProtectionsConsumer />
        </ProtectionsProvider>
    );
}
