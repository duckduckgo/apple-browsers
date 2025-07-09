import styles from './InfoBar.module.css';
import { h } from 'preact';
import dax from '../img/dax.data.svg';
import info from '../img/info.data.svg';
import cog from '../img/cog.data.svg';
import { Button, ButtonLink, Icon } from './Button.jsx';
import { SwitchBarDesktop } from './SwitchBarDesktop.jsx';
import { useOpenOnYoutubeHandler, useSettingsUrl } from '../providers/SettingsProvider.jsx';
import { useContext, useLayoutEffect, useRef, useState } from 'preact/hooks';
import { SwitchContext, SwitchProvider } from '../providers/SwitchProvider.jsx';
import { Tooltip } from './Tooltip.jsx';
import { useSetFocusMode } from './FocusMode.jsx';
import { useTypedTranslation } from '../types.js';
import { useShowCustomError } from '../providers/YouTubeErrorProvider';

/**
 * @param {object} props
 * @param {import("../embed-settings.js").EmbedSettings|null} props.embed
 */
export function InfoBar({ embed }) {
    const showCustomError = useShowCustomError();
    return (
        <div class={styles.infoBar}>
            <div class={styles.lhs}>
                <div class={styles.dax}>
                    <img src={dax} class={styles.img} />
                </div>
                <div class={styles.text}>Duck Player</div>
                <InfoIcon />
            </div>
            <div class={styles.rhs}>
                <SwitchProvider>
                    {!showCustomError && (
                        <div class={styles.switch}>
                            <SwitchBarDesktop />
                        </div>
                    )}
                    <ControlBarDesktop embed={embed} />
                </SwitchProvider>
            </div>
        </div>
    );
}

/**
 * @param {object} props
 * @param {boolean} [props.debugStyles]
 */
export function InfoIcon({ debugStyles = false }) {
    const setFocusMode = useSetFocusMode();
    const [isVisible, setIsVisible] = useState(debugStyles);
    const [isBottom, setIsBottom] = useState(false);
    /**
     * @type {import("preact/hooks").MutableRef<HTMLButtonElement|null>}
     */
    const tooltipRef = useRef(null);

    function show() {
        setIsVisible(true);
        setFocusMode('paused');
    }
    function hide() {
        setIsVisible(false);
        setFocusMode('enabled');
    }

    useLayoutEffect(() => {
        if (!tooltipRef.current) return;
        const icon = tooltipRef.current;
        const rect = icon.getBoundingClientRect();

        const iconTop = rect.top + window.scrollY;
        const spaceBelowIcon = window.innerHeight - iconTop;

        if (spaceBelowIcon < 125) {
            return setIsBottom(false);
        }

        return setIsBottom(true);
    }, [isVisible]);

    return (
        <button
            className={styles.info}
            aria-describedby="tooltip1"
            aria-expanded={isVisible}
            aria-label="Info"
            onMouseEnter={show}
            onMouseLeave={hide}
            onFocus={show} // for keyboard accessibility
            onBlur={hide} // for keyboard accessibility
            ref={tooltipRef}
        >
            <Icon src={info} />
            <Tooltip id="tooltip1" isVisible={isVisible} position={isBottom ? 'bottom' : 'top'} />
        </button>
    );
}

/**
 * @param {object} props
 * @param {import("../embed-settings.js").EmbedSettings|null} props.embed
 */
function ControlBarDesktop({ embed }) {
    const settingsUrl = useSettingsUrl();
    const openOnYoutube = useOpenOnYoutubeHandler();
    const showCustomError = useShowCustomError(); // When there's a YouTube error, the watch on YouTube button is shown in the error screen instead

    const { t } = useTypedTranslation();
    const { state } = useContext(SwitchContext);
    return (
        <div className={styles.controls}>
            <ButtonLink
                formfactor={'desktop'}
                icon={true}
                highlight={state === 'exiting'}
                anchorProps={{
                    href: settingsUrl,
                    target: '_blank',
                    'aria-label': t('openSettingsButton'),
                }}
            >
                <Icon src={cog} />
            </ButtonLink>
            {!showCustomError && (
                <Button
                    formfactor={'desktop'}
                    buttonProps={{
                        onClick: () => {
                            if (embed) openOnYoutube(embed);
                        },
                    }}
                >
                    {t('watchOnYoutube')}
                </Button>
            )}
        </div>
    );
}

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function InfoBarContainer({ children }) {
    return <div class={styles.container}>{children}</div>;
}
