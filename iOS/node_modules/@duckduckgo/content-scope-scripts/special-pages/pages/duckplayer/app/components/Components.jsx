import { Fragment, h } from 'preact';
import styles from './Components.module.css';
import { PlayerContainer, PlayerInternal } from './PlayerContainer.jsx';
import info from '../img/info.data.svg';
import cog from '../img/cog.data.svg';
import { Button, Icon } from './Button.jsx';
import { FloatingBar } from './FloatingBar.jsx';
import { SwitchBarMobile } from './SwitchBarMobile.jsx';
import { InfoBar, InfoBarContainer, InfoIcon } from './InfoBar.jsx';
import { Wordmark } from './Wordmark.jsx';
import { Player, PlayerError } from './Player.jsx';
import { SettingsProvider } from '../providers/SettingsProvider.jsx';
import { Settings } from '../settings.js';
import { EmbedSettings } from '../embed-settings.js';
import { SwitchBarDesktop } from './SwitchBarDesktop.jsx';
import { SwitchProvider } from '../providers/SwitchProvider.jsx';
import { YouTubeError } from './YouTubeError';
import { YouTubeErrorProvider } from '../providers/YouTubeErrorProvider';

export function Components() {
    const settings = new Settings({
        platform: { name: 'macos' },
        customError: { state: 'enabled' },
    });
    let embed = /** @type {EmbedSettings} */ (EmbedSettings.fromHref('https://localhost?videoID=123'));
    let url = embed?.toEmbedUrl();
    if (!url) throw new Error('unreachable');
    return (
        <>
            <main class={styles.main}>
                <div class={styles.tube}>
                    <Wordmark />
                    <h2>Floating Bar</h2>
                    <div style="position: relative; padding-left: 10em; min-height: 150px;">
                        <InfoIcon debugStyles={true} />
                    </div>

                    <h2>Info Tooltip</h2>

                    <FloatingBar>
                        <Button icon={true}>
                            <Icon src={info} />
                        </Button>
                        <Button icon={true}>
                            <Icon src={cog} />
                        </Button>
                        <Button fill={true}>Open in YouTube</Button>
                    </FloatingBar>

                    <h2>Info Bar</h2>
                    <SettingsProvider settings={settings}>
                        <SwitchProvider>
                            <InfoBar embed={embed} />
                        </SwitchProvider>
                    </SettingsProvider>
                    <br />

                    <h2>Mobile Switch Bar (ios)</h2>
                    <SwitchProvider>
                        <SwitchBarMobile platformName={'ios'} />
                    </SwitchProvider>

                    <h2>Mobile Switch Bar (android)</h2>
                    <SwitchProvider>
                        <SwitchBarMobile platformName={'android'} />
                    </SwitchProvider>

                    <h2>Desktop Switch bar</h2>
                    <h3>idle</h3>
                    <SwitchProvider>
                        <SwitchBarDesktop />
                    </SwitchProvider>
                </div>
                <h2>
                    <code>inset=false (desktop)</code>
                </h2>
                <SettingsProvider settings={settings}>
                    <PlayerContainer>
                        <Player src={url} layout={'desktop'} embed={embed} />
                        <InfoBarContainer>
                            <InfoBar embed={embed} />
                        </InfoBarContainer>
                    </PlayerContainer>
                </SettingsProvider>
                <br />

                <SettingsProvider settings={settings}>
                    <YouTubeErrorProvider initial={'sign-in-required'} locale="en">
                        <PlayerContainer>
                            <YouTubeError layout={'desktop'} />
                            <InfoBarContainer>
                                <InfoBar embed={embed} />
                            </InfoBarContainer>
                        </PlayerContainer>
                    </YouTubeErrorProvider>
                </SettingsProvider>
                <br />

                <SettingsProvider settings={settings}>
                    <YouTubeErrorProvider initial={'age-restricted'} locale="en">
                        <PlayerContainer>
                            <YouTubeError layout={'desktop'} />
                            <InfoBarContainer>
                                <InfoBar embed={embed} />
                            </InfoBarContainer>
                        </PlayerContainer>
                    </YouTubeErrorProvider>
                </SettingsProvider>
                <br />

                <SettingsProvider settings={settings}>
                    <YouTubeErrorProvider initial={'no-embed'} locale="en">
                        <PlayerContainer>
                            <YouTubeError layout={'desktop'} />
                            <InfoBarContainer>
                                <InfoBar embed={embed} />
                            </InfoBarContainer>
                        </PlayerContainer>
                    </YouTubeErrorProvider>
                </SettingsProvider>
                <br />

                <SettingsProvider settings={settings}>
                    <YouTubeErrorProvider initial={'unknown'} locale="en">
                        <PlayerContainer>
                            <YouTubeError layout={'desktop'} />
                            <InfoBarContainer>
                                <InfoBar embed={embed} />
                            </InfoBarContainer>
                        </PlayerContainer>
                    </YouTubeErrorProvider>
                </SettingsProvider>
                <br />

                <SettingsProvider settings={settings}>
                    <YouTubeErrorProvider initial={'unknown'} locale="es">
                        <PlayerContainer>
                            <YouTubeError layout={'desktop'} />
                            <InfoBarContainer>
                                <InfoBar embed={embed} />
                            </InfoBarContainer>
                        </PlayerContainer>
                    </YouTubeErrorProvider>
                </SettingsProvider>
                <br />

                <h2>
                    <code>inset=true (mobile)</code>
                </h2>
                <PlayerContainer inset>
                    <PlayerInternal inset>
                        <PlayerError layout={'mobile'} kind={'invalid-id'} />
                        <SwitchBarMobile platformName={'ios'} />
                    </PlayerInternal>
                </PlayerContainer>
                <br />

                <YouTubeErrorProvider initial={'sign-in-required'} locale="en">
                    <PlayerContainer inset>
                        <PlayerInternal inset>
                            <YouTubeError layout={'mobile'} />
                            <SwitchBarMobile platformName={'ios'} />
                        </PlayerInternal>
                    </PlayerContainer>
                </YouTubeErrorProvider>
                <br />

                <YouTubeErrorProvider initial={'age-restricted'} locale="en">
                    <PlayerContainer inset>
                        <PlayerInternal inset>
                            <YouTubeError layout={'mobile'} />
                            <SwitchBarMobile platformName={'ios'} />
                        </PlayerInternal>
                    </PlayerContainer>
                </YouTubeErrorProvider>
                <br />

                <YouTubeErrorProvider initial={'no-embed'} locale="en">
                    <PlayerContainer inset>
                        <PlayerInternal inset>
                            <YouTubeError layout={'mobile'} />
                            <SwitchBarMobile platformName={'ios'} />
                        </PlayerInternal>
                    </PlayerContainer>
                </YouTubeErrorProvider>
                <br />

                <YouTubeErrorProvider initial={'unknown'} locale="en">
                    <PlayerContainer inset>
                        <PlayerInternal inset>
                            <YouTubeError layout={'mobile'} />
                            <SwitchBarMobile platformName={'ios'} />
                        </PlayerInternal>
                    </PlayerContainer>
                </YouTubeErrorProvider>
                <br />

                <YouTubeErrorProvider initial={'unknown'} locale="es">
                    <PlayerContainer inset>
                        <PlayerInternal inset>
                            <YouTubeError layout={'mobile'} />
                            <SwitchBarMobile platformName={'ios'} />
                        </PlayerInternal>
                    </PlayerContainer>
                </YouTubeErrorProvider>
                <br />
            </main>
        </>
    );
}
