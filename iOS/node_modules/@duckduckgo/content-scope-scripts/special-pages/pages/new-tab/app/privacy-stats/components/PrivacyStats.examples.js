import { Fragment, h } from 'preact';
import { BodyExpansionMockProvider, PrivacyStatsMockProvider } from '../mocks/PrivacyStatsMockProvider.js';
import { ListFooter, PrivacyStats } from './PrivacyStats.js';
import { privacyStatsMocks } from '../mocks/privacy-stats.mocks.js';
import { PrivacyStatsConsumer } from './PrivacyStatsConsumer.js';

/** @type {Record<string, {factory: () => import("preact").ComponentChild}>} */

export const privacyStatsExamples = {
    'stats.few': {
        factory: () => (
            <PrivacyStatsMockProvider ticker={true}>
                <PrivacyStatsConsumer />
            </PrivacyStatsMockProvider>
        ),
    },
    'stats.few.collapsed': {
        factory: () => (
            <PrivacyStatsMockProvider>
                <PrivacyStatsConsumer />
            </PrivacyStatsMockProvider>
        ),
    },
    'stats.single': {
        factory: () => (
            <PrivacyStatsMockProvider data={privacyStatsMocks.single}>
                <PrivacyStatsConsumer />
            </PrivacyStatsMockProvider>
        ),
    },
    'stats.none': {
        factory: () => (
            <PrivacyStatsMockProvider data={privacyStatsMocks.none}>
                <PrivacyStatsConsumer />
            </PrivacyStatsMockProvider>
        ),
    },
    'stats.norecent': {
        factory: () => (
            <PrivacyStatsMockProvider data={privacyStatsMocks.norecent}>
                <PrivacyStatsConsumer />
            </PrivacyStatsMockProvider>
        ),
    },
    'stats.list': {
        factory: () => <PrivacyStats trackerCompanies={privacyStatsMocks.few.trackerCompanies} expansion={'expanded'} />,
    },
    'stats.footer': {
        factory: () => {
            const data = privacyStatsMocks.manyTopAndOther.trackerCompanies;
            return (
                <Fragment>
                    <h2>Collapsed</h2>
                    <br />
                    <BodyExpansionMockProvider bodyExpansion={'collapsed'}>
                        <ListFooter all={data} />
                    </BodyExpansionMockProvider>
                    <br />
                    <h2>Expanded</h2>
                    <br />
                    <BodyExpansionMockProvider bodyExpansion={'expanded'}>
                        <ListFooter all={data} />
                    </BodyExpansionMockProvider>
                </Fragment>
            );
        },
    },
};

export const otherPrivacyStatsExamples = {
    'stats.all': {
        factory: () => {
            const names = Object.keys(privacyStatsMocks);
            return (
                <Fragment>
                    {names.map((key) => {
                        return (
                            <Fragment key={key}>
                                <h2>{key}</h2>
                                <br />
                                <PrivacyStatsMockProvider data={privacyStatsMocks[key]}>
                                    <PrivacyStatsConsumer />
                                </PrivacyStatsMockProvider>
                            </Fragment>
                        );
                    })}
                </Fragment>
            );
        },
    },
    'stats.manyTopAndOther': {
        factory: () => (
            <Fragment>
                <h2>manyOnlyTop</h2>
                <br />
                <PrivacyStatsMockProvider data={privacyStatsMocks.manyTopAndOther}>
                    <PrivacyStatsConsumer />
                </PrivacyStatsMockProvider>
                <h2>manyOnlyTop + body expanded</h2>
                <br />
                <PrivacyStatsMockProvider data={privacyStatsMocks.manyTopAndOther} bodyExpansion={'expanded'}>
                    <PrivacyStatsConsumer />
                </PrivacyStatsMockProvider>
            </Fragment>
        ),
    },
};
