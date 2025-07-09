import { h } from 'preact';
import cn from 'classnames';
import { Settings } from '../settings';
import { useTypedTranslation } from '../types.js';
import { Button, OpenInIcon } from './Button.jsx';
import { useOpenOnYoutubeHandler } from '../providers/SettingsProvider.jsx';

import styles from './YouTubeError.module.css';
import { useLocale, useYouTubeError } from '../providers/YouTubeErrorProvider';

/**
 * @typedef {import('../../types/duckplayer').YouTubeError} YouTubeError
 * @typedef {import('preact').ComponentChild} ComponentChild
 * @typedef {{heading: ComponentChild, messages: ComponentChild[], variant: 'list'|'inline'|'paragraphs'}} ErrorStrings
 */

/**
 * @param {YouTubeError} youtubeError
 * @returns {ErrorStrings}
 */
function useErrorStrings(youtubeError) {
    const { t } = useTypedTranslation();

    // This versioning setup exists in case we need to experiment with copy variants in the future. At the moment, v2 is used everywhere.
    const version = 'v2';

    /**
     * @type {Record<string, Partial<Record<YouTubeError, ErrorStrings>>  & { unknown: ErrorStrings }>}
     */
    const versions = {
        v1: {
            'sign-in-required': {
                heading: t('blockedVideoErrorHeading'),
                messages: [t('signInRequiredErrorMessage1'), t('signInRequiredErrorMessage2')],
                variant: 'paragraphs',
            },
            unknown: {
                heading: t('blockedVideoErrorHeading'),
                messages: [t('blockedVideoErrorMessage1'), t('blockedVideoErrorMessage2')],
                variant: 'paragraphs',
            },
        },
        v2: {
            'sign-in-required': {
                heading: t('signInRequiredErrorHeading2'),
                messages: [t('signInRequiredErrorMessage2a'), t('signInRequiredErrorMessage2b')],
                variant: 'paragraphs',
            },
            'age-restricted': {
                heading: t('ageRestrictedErrorHeading2'),
                messages: [t('ageRestrictedErrorMessage2a'), t('ageRestrictedErrorMessage2b')],
                variant: 'paragraphs',
            },
            'no-embed': {
                heading: t('noEmbedErrorHeading2'),
                messages: [t('noEmbedErrorMessage2a'), t('noEmbedErrorMessage2b')],
                variant: 'paragraphs',
            },
            unknown: {
                heading: t('unknownErrorHeading2'),
                messages: [t('unknownErrorMessage2a'), t('unknownErrorMessage2b')],
                variant: 'paragraphs',
            },
        },
    };

    return versions[version]?.[youtubeError] || versions[version]?.['unknown'] || versions['v1']['unknown'];
}

/**
 * @param {object} props
 * @param {Settings['layout']} props.layout
 * @param {import("../embed-settings.js").EmbedSettings|null} [props.embed]
 */
export function YouTubeError({ layout, embed }) {
    const youtubeError = useYouTubeError();
    if (!youtubeError) {
        return null;
    }

    const { t } = useTypedTranslation();
    const openOnYoutube = useOpenOnYoutubeHandler();
    const { heading, messages, variant } = useErrorStrings(youtubeError);
    const classes = cn(styles.error, {
        [styles.desktop]: layout === 'desktop',
        [styles.mobile]: layout === 'mobile',
    });

    return (
        <div className={classes}>
            <div className={styles.container}>
                <span className={styles.icon}></span>

                <div className={styles.content} data-testid="YouTubeErrorContent">
                    <h1 className={styles.heading}>{heading}</h1>

                    {messages && variant === 'inline' && (
                        <p className={styles.messages}>
                            {messages.map((item) => (
                                <span key={item}>{item}</span>
                            ))}
                        </p>
                    )}

                    {messages && variant === 'paragraphs' && (
                        <div className={styles.messages}>
                            {messages.map((item) => (
                                <p key={item}>{item}</p>
                            ))}
                        </div>
                    )}

                    {messages && variant === 'list' && (
                        <ul className={styles.messages}>
                            {messages.map((item) => (
                                <li key={item}>{item}</li>
                            ))}
                        </ul>
                    )}

                    {embed && layout === 'desktop' && (
                        <div className={styles.buttons}>
                            <span className={styles.spacer}></span>
                            <Button
                                formfactor={'desktop'}
                                variant={'accent'}
                                buttonProps={{
                                    onClick: () => {
                                        openOnYoutube(embed);
                                    },
                                }}
                            >
                                <OpenInIcon />
                                {t('watchOnYoutube')}
                            </Button>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}
