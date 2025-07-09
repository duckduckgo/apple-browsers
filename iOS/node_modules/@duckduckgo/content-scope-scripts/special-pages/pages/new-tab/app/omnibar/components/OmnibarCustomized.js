import { useTypedTranslationWith } from '../../types.js';
import { useVisibility } from '../../widget-list/widget-config.provider.js';
import { useCustomizer } from '../../customizer/components/CustomizerMenu.js';
import { OmnibarProvider } from './OmnibarProvider.js';
import { h } from 'preact';

import { OmnibarConsumer } from './OmnibarConsumer.js';

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
export function OmnibarCustomized() {
    const { t } = useTypedTranslationWith(/** @type {Strings} */ ({}));

    /**
     * The menu title for the omnibar widget.
     */
    const sectionTitle = t('omnibar_menuTitle');

    const { visibility, id, toggle, index } = useVisibility();

    useCustomizer({ title: sectionTitle, id, icon: 'search', toggle, visibility: visibility.value, index });

    if (visibility.value === 'hidden') {
        return null;
    }

    return (
        <OmnibarProvider>
            <OmnibarConsumer />
        </OmnibarProvider>
    );
}
