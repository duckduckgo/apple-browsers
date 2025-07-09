import { h, Fragment } from 'preact';
import cn from 'classnames';
import styles from './MobileApp.module.css';
import { Player, PlayerError } from './Player.jsx';
import { YouTubeError } from './YouTubeError';
import { usePlatformName, useSettings } from '../providers/SettingsProvider.jsx';
import { SwitchBarMobile } from './SwitchBarMobile.jsx';
import { MobileWordmark } from './Wordmark.jsx';
import { SwitchProvider } from '../providers/SwitchProvider.jsx';
import { createAppFeaturesFrom } from '../features/app.js';
import { MobileButtons } from './MobileButtons.jsx';
import { OrientationProvider } from '../providers/OrientationProvider.jsx';
import { FocusMode } from './FocusMode.jsx';
import { useTelemetry } from '../types.js';
import { useShowCustomError } from '../providers/YouTubeErrorProvider';

const DISABLED_HEIGHT = 450;

/**
 * @param {object} props
 * @param {import("../embed-settings.js").EmbedSettings|null} props.embed
 */
export function MobileApp({ embed }) {
    const settings = useSettings();
    const telemetry = useTelemetry();
    const showCustomError = useShowCustomError();
    const features = createAppFeaturesFrom(settings);

    return (
        <>
            {!showCustomError && features.focusMode()}
            <OrientationProvider
                onChange={(orientation) => {
                    if (showCustomError) return;

                    if (orientation === 'portrait') {
                        return FocusMode.enable();
                    }
                    // landscape
                    // if the height is too low, just disable it
                    if (window.innerHeight < DISABLED_HEIGHT) {
                        FocusMode.disable();
                        telemetry.landscapeImpression();
                        return;
                    }
                    return FocusMode.enable();
                }}
            />
            <MobileLayout embed={embed} />
        </>
    );
}

/**
 * @param {object} props
 * @param {import("../embed-settings.js").EmbedSettings|null} props.embed
 */
function MobileLayout({ embed }) {
    const platformName = usePlatformName();
    const showCustomError = useShowCustomError();

    return (
        <main class={styles.main} data-youtube-error={showCustomError}>
            <div class={cn(styles.filler, styles.hideInFocus)} />
            <div class={styles.embed}>
                {embed === null && <PlayerError layout={'mobile'} kind={'invalid-id'} />}
                {embed !== null && showCustomError && <YouTubeError layout={'mobile'} embed={embed} />}
                {embed !== null && !showCustomError && <Player src={embed.toEmbedUrl()} layout={'mobile'} embed={embed} />}
            </div>
            <div class={cn(styles.logo, styles.hideInFocus)}>
                <MobileWordmark />
            </div>
            <div class={cn(styles.switch, styles.hideInFocus)}>
                {!showCustomError && (
                    <SwitchProvider>
                        <SwitchBarMobile platformName={platformName} />
                    </SwitchProvider>
                )}
            </div>
            <div class={cn(styles.buttons, styles.hideInFocus)}>
                <MobileButtons embed={embed} accentedWatchButton={embed !== null && showCustomError} />
            </div>
        </main>
    );
}
