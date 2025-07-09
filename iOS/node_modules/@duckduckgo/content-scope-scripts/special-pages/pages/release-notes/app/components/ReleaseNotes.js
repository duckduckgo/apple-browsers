import { Fragment, h } from 'preact';
import classNames from 'classnames';
import { useMessaging } from '../index';
import { useTypedTranslation } from '../types';
import { Button } from '../../../../shared/components/Button/Button';
import { Card } from '../../../../shared/components/Card/Card';
// eslint-disable-next-line no-redeclare
import { Text } from '../../../../shared/components/Text/Text';
import { usePlatformName } from '../settings.provider';
import { ContentPlaceholder } from './ContentPlaceholder';
import OpenInIcon from './OpenIn16';

import styles from './ReleaseNotes.module.css';

/**
 * @typedef {import('../../types/release-notes.js').UpdateMessage} UpdateMessage
 * @typedef {import('../../types/release-notes.js').UpdateErrorState} UpdateErrorState
 * @typedef {import('../../types/release-notes.js').UpdateReadyState} UpdateReadyState
 * @typedef {import('../../types/release-notes.js').ReleaseNotesLoadingErrorState} ReleaseNotesLoadingErrorState
 * @typedef {import('../../types/release-notes.js').ReleaseNotesLoadedState} ReleaseNotesLoadedState
 * @typedef {import('../types.js').Notes} Notes
 */

/**
 * @param {object} props
 * @param {string} props.title
 */
export function PageTitle({ title }) {
    return <h1 className={styles.title}>{title}</h1>;
}

/**
 * @param {object} props
 * @param {UpdateMessage['status']} props.status
 * @param {string} props.version
 * @param {number} [props.progress] - download progress as a number from 0 to 1
 */
function StatusText({ status, version, progress = 0 }) {
    const { t } = useTypedTranslation();
    const progressPercentage = (progress * 100).toFixed(0);

    /** @type {Record<UpdateMessage['status'],string>} */
    const statusTexts = {
        loaded: t('browserUpToDate'),
        loading: t('checkingForUpdate'),
        loadingError: t('loadingError'),
        updateReady: t('newVersionAvailable'),
        updateError: t('updateError'),
        criticalUpdateReady: t('criticallyOutOfDate'),
        updateDownloading: t('updateDownloading', { progress: progressPercentage }),
        updatePreparing: t('updatePreparing'),
    };

    return (
        <Text variant="title-2" className={styles.statusText}>
            {t('versionNumber', { version: `${version}` })} — {statusTexts[status]}
        </Text>
    );
}

/**
 * @param {object} props
 * @param {UpdateMessage['status']} props.status
 * @param {string} [props.className]
 */
function StatusIcon({ status, className }) {
    /** @type {Record<UpdateMessage['status'],string>} */
    const iconClasses = {
        loaded: styles.checkIcon,
        loading: styles.spinnerIcon,
        loadingError: styles.warningIcon,
        updateReady: styles.alertIcon,
        criticalUpdateReady: styles.warningIcon,
        updateError: styles.warningIcon,
        updatePreparing: styles.spinnerIcon,
        updateDownloading: styles.spinnerIcon,
    };

    return <div className={classNames(styles.statusIcon, iconClasses[status], className)} />;
}

/**
 * @param {object} props
 * @param {number} props.timestamp - in milliseconds
 */
function StatusTimestamp({ timestamp }) {
    const { t } = useTypedTranslation();

    const date = new Date(timestamp);
    const today = new Date();
    const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000);

    const timeString = date.toLocaleTimeString('en', { timeStyle: 'short' });
    let dateString = `${date.toLocaleDateString('en', { dateStyle: 'full' })} ${timeString}`;

    if (
        date.getDate() === yesterday.getDate() &&
        date.getMonth() === yesterday.getMonth() &&
        date.getFullYear() === yesterday.getFullYear()
    ) {
        dateString = t('yesterdayAt', { time: timeString });
    }

    if (date.getDate() === today.getDate() && date.getMonth() === today.getMonth() && date.getFullYear() === today.getFullYear()) {
        dateString = t('todayAt', { time: timeString });
    }

    return (
        <Text variant="body" className={styles.statusTimestamp}>
            {t('lastChecked', { date: dateString })}
        </Text>
    );
}

/**
 * @param {object} props
 * @param {UpdateMessage['status']} props.status
 * @param {number} props.timestamp - in milliseconds
 * @param {string} props.version
 * @param {number} [props.progress] - download progress as a number from 0 to 1
 */
export function UpdateStatus({ status, timestamp, version, progress }) {
    return (
        <div className={styles.statusContainer}>
            <StatusIcon status={status} className={styles.gridIcon} />
            <StatusText status={status} version={version} progress={progress} />
            <StatusTimestamp timestamp={timestamp} />
        </div>
    );
}

/**
 * @param {Object} props
 * @param {string} props.title
 * @param {string} props.version
 * @param {boolean} [props.showNewTag]
 */
export function ReleaseNotesHeading({ title, version, showNewTag = false }) {
    const { t } = useTypedTranslation();

    return (
        <header className={styles.notesHeading}>
            <h2 className={styles.releaseTitle}>
                {title}
                {showNewTag && <span className={styles.newTag}>{t('new')}</span>}
            </h2>
            <Text variant="title-2" className={styles.releaseVersion}>
                {t('versionNumber', { version: `${version}` })}
            </Text>
        </header>
    );
}

/**
 * @param {Omit<Notes, 'notes'>} props
 */
export function ReleaseNotesSubheading({ icon, title }) {
    return (
        <div className={styles.notesSubheading}>
            {icon && <span className={classNames(styles.notesIcon, styles[`notesIcon${icon}`])} />}
            <Text as="h3" variant="headline">
                {title}
            </Text>
        </div>
    );
}

/**
 * @param {Object} props
 * @param {import("preact").ComponentChild[]} props.notes
 */
export function ReleaseNotesList({ notes }) {
    return (
        <ul className={styles.list}>
            {notes.map((note) => (
                <Text as="li" variant="body" className={styles.listItem}>
                    {note}
                </Text>
            ))}
        </ul>
    );
}

/**
 * @param {Object} props
 * @param {string} [props.title]
 * @param {string} props.currentVersion
 * @param {string} [props.latestVersion]
 * @param {Notes[]} props.notes
 */
export function ReleaseNotesContent({ title: releaseTitle, currentVersion, latestVersion, notes: releaseNotes }) {
    if (!releaseTitle || !releaseNotes.length) return null;
    const version = latestVersion || currentVersion;
    const showNewTag = !!latestVersion && currentVersion !== latestVersion;

    return (
        <Fragment>
            <ReleaseNotesHeading title={releaseTitle} version={version} showNewTag={showNewTag} />
            <div className={styles.listGrid}>
                {releaseNotes.map(({ icon, title, notes }) => (
                    <div class={styles.listContainer}>
                        {title && <ReleaseNotesSubheading title={title} icon={icon} />}
                        <ReleaseNotesList notes={notes} />
                    </div>
                ))}
            </div>
        </Fragment>
    );
}

/**
 * Parses release notes data and shows either the loading placeholder or a Release Notes card
 *
 * @param {object} props
 * @param {UpdateMessage} props.releaseData
 */
export function CardContents({ releaseData }) {
    const { t } = useTypedTranslation();
    const { status } = releaseData;
    const isLoading = status === 'loading' || status === 'updateDownloading' || status === 'updatePreparing';

    if (isLoading || status === 'loadingError') {
        return <ContentPlaceholder />;
    }

    /**
     * @type {Notes[]}
     */
    const notes = [];

    const { currentVersion, latestVersion, releaseTitle, releaseNotes, releaseNotesPrivacyPro } = releaseData;

    if (releaseNotes?.length) {
        notes.push({ notes: releaseNotes });
    }

    if (releaseNotesPrivacyPro?.length) {
        notes.push({
            icon: 'PrivacyPro',
            title: t('forPrivacyProSubscribers'),
            notes: [
                ...releaseNotesPrivacyPro,
                /* The following should only get translated when the contents of the Release Notes update message are localized */
                <span>
                    Not subscribed? Find out more at{' '}
                    <a href="https://duckduckgo.com/pro" target="_blank">
                        duckduckgo.com/pro
                    </a>
                </span>,
            ],
        });
    }

    return <ReleaseNotesContent title={releaseTitle} currentVersion={currentVersion} latestVersion={latestVersion} notes={notes} />;
}

/**
 * @param {object} props
 * @param {UpdateReadyState|UpdateErrorState|ReleaseNotesLoadingErrorState} props.releaseData
 */
export function UpdateButton({ releaseData }) {
    const { t } = useTypedTranslation();
    const { messages } = useMessaging();
    const platform = usePlatformName();

    const { status } = releaseData;
    let button;

    if (status === 'loadingError') {
        button = (
            <Button onClick={() => messages?.retryFetchReleaseNotes()} variant="accentBrand" size={platform === 'macos' ? 'lg' : 'md'}>
                {t('retryGettingReleaseNotes')}
            </Button>
        );
    }

    if (status === 'updateError') {
        button = (
            <Button onClick={() => messages?.retryUpdate()} variant="accentBrand" size={platform === 'macos' ? 'lg' : 'md'}>
                {t('retryUpdate')}
            </Button>
        );
    }

    if (status === 'updateReady' || status === 'criticalUpdateReady') {
        const { automaticUpdate } = releaseData;
        const buttonText = automaticUpdate ? t('restartToUpdate') : t('updateBrowser');

        button = (
            <Button onClick={() => messages?.browserRestart()} variant="accentBrand" size={platform === 'macos' ? 'lg' : 'md'}>
                {buttonText}
            </Button>
        );
    }

    if (!button) return null;

    return <div className={styles.buttonContainer}>{button}</div>;
}

/**
 * @param {object} props
 * @param {UpdateMessage} props.releaseData
 */
export function ReleaseNotes({ releaseData }) {
    const { t } = useTypedTranslation();

    const { status, currentVersion, lastUpdate } = releaseData;
    const timestampInMilliseconds = lastUpdate * 1000;

    let progress = 0;
    if (status === 'updateDownloading') {
        const { downloadProgress } = releaseData;

        if (downloadProgress && !Number.isNaN(downloadProgress)) {
            progress = downloadProgress;
        } else {
            console.warn('Invalid download progress value in data');
        }
    }

    const shouldShowButton =
        status === 'updateReady' || status === 'criticalUpdateReady' || status === 'updateError' || status === 'loadingError';

    return (
        <article className={styles.article}>
            <header className={styles.heading}>
                <p>{t('thankyou')}</p>
                <PageTitle title={t('browserReleaseNotes')} />
                <UpdateStatus status={status} timestamp={timestampInMilliseconds} version={currentVersion} progress={progress} />
                {shouldShowButton && <UpdateButton releaseData={releaseData} />}
            </header>
            {status !== 'loadingError' && (
                <Card className={styles.card}>
                    <CardContents releaseData={releaseData} />
                </Card>
            )}
            <a href="https://duckduckgo.com/updates" target="_blank" className={styles.updatesLink}>
                {t('whatsNewAtDuckDuckGoLink')}
                <OpenInIcon className={styles.linkIcon} />
            </a>
        </article>
    );
}
