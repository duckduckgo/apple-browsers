import { h, Fragment } from 'preact';
import styles from './DesktopApp.module.css';
import { InfoBar, InfoBarContainer } from './InfoBar.jsx';
import { PlayerContainer } from './PlayerContainer.jsx';
import { Player, PlayerError } from './Player.jsx';
import { YouTubeError } from './YouTubeError';
import { useSettings } from '../providers/SettingsProvider.jsx';
import { createAppFeaturesFrom } from '../features/app.js';
import { HideInFocusMode } from './FocusMode.jsx';
import { useShowCustomError } from '../providers/YouTubeErrorProvider';

/**
 * @param {object} props
 * @param {import("../embed-settings.js").EmbedSettings|null} props.embed
 */
export function DesktopApp({ embed }) {
    const settings = useSettings();
    const features = createAppFeaturesFrom(settings);
    const showCustomError = useShowCustomError();

    return (
        <>
            {features.focusMode()}
            <main class={styles.app} data-youtube-error={showCustomError}>
                <DesktopLayout embed={embed} />
            </main>
        </>
    );
}

/**
 * @param {object} props
 * @param {import("../embed-settings.js").EmbedSettings|null} props.embed
 */
function DesktopLayout({ embed }) {
    const showCustomError = useShowCustomError();

    return (
        <div class={styles.desktop}>
            <PlayerContainer>
                {embed === null && <PlayerError layout={'desktop'} kind={'invalid-id'} />}
                {embed !== null && showCustomError && <YouTubeError layout={'desktop'} embed={embed} />}
                {embed !== null && !showCustomError && <Player src={embed.toEmbedUrl()} layout={'desktop'} embed={embed} />}
                <HideInFocusMode style={'slide'}>
                    <InfoBarContainer>
                        <InfoBar embed={embed} />
                    </InfoBarContainer>
                </HideInFocusMode>
            </PlayerContainer>
        </div>
    );
}
