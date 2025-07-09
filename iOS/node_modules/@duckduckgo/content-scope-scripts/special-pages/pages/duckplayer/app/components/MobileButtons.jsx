import { h } from 'preact';
import { useOpenInfoHandler, useOpenOnYoutubeHandler, useOpenSettingsHandler } from '../providers/SettingsProvider.jsx';
import { useTypedTranslation } from '../types.js';
import { Button, Icon } from './Button.jsx';

import styles from './MobileButtons.module.css';
import info from '../img/info.data.svg';
import cog from '../img/cog.data.svg';

/**
 * @param {object} props
 * @param {import("../embed-settings.js").EmbedSettings|null} props.embed
 * @param {boolean} [props.accentedWatchButton]
 */
export function MobileButtons({ embed, accentedWatchButton = false }) {
    const openSettings = useOpenSettingsHandler();
    const openInfo = useOpenInfoHandler();
    const openOnYoutube = useOpenOnYoutubeHandler();
    const { t } = useTypedTranslation();
    return (
        <div class={styles.buttons}>
            <Button
                icon={true}
                buttonProps={{
                    'aria-label': t('openInfoButton'),
                    onClick: openInfo,
                }}
            >
                <Icon src={info} />
            </Button>
            <Button
                icon={true}
                buttonProps={{
                    'aria-label': t('openSettingsButton'),
                    onClick: openSettings,
                }}
            >
                <Icon src={cog} />
            </Button>
            <Button
                fill={true}
                variant={accentedWatchButton ? 'accent' : 'standard'}
                buttonProps={{
                    onClick: () => {
                        if (embed) openOnYoutube(embed);
                    },
                }}
            >
                {t('watchOnYoutube')}
            </Button>
        </div>
    );
}
