import { h } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { Button } from '../../../shared/components/Button/Button';
import { Card } from '../../../shared/components/Card/Card';
import { DuckDuckGoLogo } from '../../../shared/components/DuckDuckGoLogo/DuckDuckGoLogo';
import { useEnv } from '../../../shared/components/EnvironmentProvider';
import { useTypedTranslation } from '../app/types';
import styles from './Components.module.css';
import { ContentPlaceholder } from './components/ContentPlaceholder';
import {
    PageTitle,
    ReleaseNotes,
    ReleaseNotesContent,
    ReleaseNotesHeading,
    ReleaseNotesList,
    ReleaseNotesSubheading,
    UpdateStatus,
} from './components/ReleaseNotes';
import { sampleData } from './sampleData.js';
import { usePlatformName } from './settings.provider';

export function Components() {
    const { t } = useTypedTranslation();
    const { isDarkMode } = useEnv();
    const platform = usePlatformName();
    const todayInMilliseconds = Date.now();
    const yesterdayInMilliseconds = new Date(todayInMilliseconds - 24 * 60 * 60 * 1000).getTime();

    /**
     * @type {import('../app/types.js').Notes[]}
     */
    const sampleNotesData = [
        {
            notes: [
                'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Cras vel viverra est. Ut non nisi lacus. Ut sodales leo sed ex condimentum tincidunt.',
                'Sed eget risus luctus, convallis sapien nec, tincidunt orci.',
                'Sed et lobortis enim. Curabitur sit amet placerat felis.',
            ],
        },
        {
            icon: 'PrivacyPro',
            title: t('forPrivacyProSubscribers'),
            notes: [
                'Cras egestas, dui eu sodales congue, ex augue vehicula ipsum, sed egestas est justo in enim.',
                'Duis varius in ex at vestibulum. Morbi finibus fringilla urna, ac varius quam vestibulum sit amet.',
                'Morbi a ligula vel metus ultrices sodales quis vel velit.',
            ],
        },
    ];

    return (
        <main className={styles.main} data-theme={isDarkMode ? 'dark' : 'light'}>
            <h1>Release Notes Components</h1>

            <h2>DuckDuckGo Logo</h2>
            <DuckDuckGoLogo />
            <hr />

            <h2>Page Title</h2>
            <PageTitle title={t('browserReleaseNotes')} />
            <hr />

            <h2>Update Status</h2>
            <UpdateStatus status="loading" version="1.0.1" timestamp={yesterdayInMilliseconds} />
            <UpdateStatus status="loadingError" version="1.0.1" timestamp={yesterdayInMilliseconds} />
            <UpdateStatus status="loaded" version="1.0.1" timestamp={todayInMilliseconds} />
            <UpdateStatus status="updateReady" version="1.2.0" timestamp={todayInMilliseconds} />
            <UpdateStatus status="criticalUpdateReady" version="1.2.0" timestamp={todayInMilliseconds} />
            <UpdateStatus status="updateError" version="1.2.0" timestamp={todayInMilliseconds} />
            <UpdateStatus status="updateDownloading" version="1.2.0" timestamp={todayInMilliseconds} progress={0.35} />
            <UpdateStatus status="updatePreparing" version="1.2.0" timestamp={todayInMilliseconds} />
            <hr />

            <h2>Update Buttons</h2>
            <div>
                <Button variant="accentBrand" size={platform === 'macos' ? 'lg' : 'md'}>
                    {t('retryGettingReleaseNotes')}
                </Button>
            </div>
            <div>
                <Button variant="accentBrand" size={platform === 'macos' ? 'lg' : 'md'}>
                    {t('restartToUpdate')}
                </Button>
            </div>
            <div>
                <Button variant="accentBrand" size={platform === 'macos' ? 'lg' : 'md'}>
                    {t('updateBrowser')}
                </Button>
            </div>
            <div>
                <Button variant="accentBrand" size={platform === 'macos' ? 'lg' : 'md'}>
                    {t('retryUpdate')}
                </Button>
            </div>
            <hr />

            <h2>Content Placeholder</h2>
            <ContentPlaceholder />
            <hr />

            <h2>Release Notes Heading</h2>
            <ReleaseNotesHeading title="May 10 2023" version="1.0.0" showNewTag={false} />
            <ReleaseNotesHeading title="May 10 2024" version="1.2.0" showNewTag={true} />
            <hr />

            <h2>Release Notes Subheading</h2>
            <ReleaseNotesSubheading title="Release Notes Subheading without Icon" />
            <ReleaseNotesSubheading icon="PrivacyPro" title="Release Notes Subheading with Privacy Pro Icon" />
            <hr />

            <h2>Release Notes List</h2>
            <ReleaseNotesList notes={sampleNotesData[0].notes} />
            <hr />

            <h2>Content Placeholder Inside a Card</h2>
            <Card className={styles.card}>
                <ContentPlaceholder />
            </Card>
            <hr />

            <h2>Release Notes Inside a Card</h2>
            <Card className={styles.card}>
                <ReleaseNotesContent title="May 10 2024" currentVersion="1.0.1" latestVersion="1.2.0" notes={sampleNotesData} />
            </Card>

            <ReleaseNotes releaseData={sampleData.loading} />
            <LoadingThen>
                <ReleaseNotes releaseData={sampleData.loaded} />
            </LoadingThen>
            <LoadingThen>
                <ReleaseNotes releaseData={sampleData.loadingError} />
            </LoadingThen>
            <LoadingThen>
                <ReleaseNotes releaseData={sampleData.updateDownloading} />
            </LoadingThen>
            <LoadingThen>
                <ReleaseNotes releaseData={sampleData.updatePreparing} />
            </LoadingThen>
            <LoadingThen>
                <ReleaseNotes releaseData={sampleData.updateError} />
            </LoadingThen>
            <LoadingThen>
                <ReleaseNotes releaseData={sampleData.updateReady} />
            </LoadingThen>
            <LoadingThen>
                <ReleaseNotes releaseData={sampleData.criticalUpdateReady} />
            </LoadingThen>
            <LoadingThen>
                <ReleaseNotes
                    releaseData={
                        /** @type {import('../types/release-notes.js').UpdateMessage} */ ({
                            ...sampleData.updateReady,
                            automaticUpdate: false,
                        })
                    }
                />
            </LoadingThen>
        </main>
    );
}

function LoadingThen({ children }) {
    const [ready, setReady] = useState(false);
    useEffect(() => {
        setTimeout(() => setReady(true), 1000);
    }, []);
    if (ready) return children;
    return <ReleaseNotes releaseData={sampleData.loading} />;
}
