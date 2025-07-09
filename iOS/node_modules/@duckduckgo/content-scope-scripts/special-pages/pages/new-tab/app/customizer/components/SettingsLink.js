import cn from 'classnames';
import styles from './CustomizerDrawerInner.module.css';
import { h } from 'preact';
import { useMessaging, useTypedTranslationWith } from '../../types.js';
import { Open } from '../../components/icons/Open.js';

/**
 * @import enStrings from '../strings.json';
 */

/**
 * Settings link
 */
export function SettingsLink() {
    const messaging = useMessaging();
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));
    function onClick(e) {
        e.preventDefault();
        messaging.open({ target: 'settings' });
    }
    return (
        <a href="duck://settings" class={cn(styles.settingsLink)} onClick={onClick}>
            <span>{t('customizer_settings_link')}</span>
            <Open />
        </a>
    );
}
