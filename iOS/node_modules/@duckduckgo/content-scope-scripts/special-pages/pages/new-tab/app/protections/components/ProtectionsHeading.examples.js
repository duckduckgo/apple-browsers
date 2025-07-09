import { Fragment, h } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { Protections } from './Protections.js';
import { useSignal } from '@preact/signals';
import { ActivityEmptyState } from '../../activity/components/Activity.js';
import { PrivacyStatsEmptyState } from '../../privacy-stats/components/PrivacyStats.js';
import { TubeGrid } from '../../components/Components.jsx';
import { SettingsProvider } from '../../settings.provider.js';
import { Settings } from '../../settings.js';

/**
 * @import {FeedType} from '../../../types/new-tab.js')
 */

export const protectionsHeadingExamples = {
    protectionsHeading: {
        factory: () => {
            return (
                <Fragment>
                    <h2>AdBlocking = "enabled"</h2>
                    <br />
                    <TubeGrid>
                        <MockWithState initial={0}>
                            {(/** @type {Mock} */ { expansion, feed, setFeed, blockedCountSignal, toggle }) => {
                                return (
                                    <SettingsProvider settings={new Settings({ adBlocking: { state: 'enabled' } })}>
                                        <Protections
                                            blockedCountSignal={blockedCountSignal}
                                            feed={feed}
                                            setFeed={setFeed}
                                            expansion={expansion}
                                            toggle={toggle}
                                        >
                                            <PrivacyStatsEmptyState />
                                        </Protections>
                                    </SettingsProvider>
                                );
                            }}
                        </MockWithState>
                        <MockWithState initial={120}>
                            {(/** @type {Mock} */ { expansion, feed, setFeed, blockedCountSignal, toggle }) => {
                                return (
                                    <SettingsProvider settings={new Settings({ adBlocking: { state: 'enabled' } })}>
                                        <Protections
                                            blockedCountSignal={blockedCountSignal}
                                            feed={feed}
                                            setFeed={setFeed}
                                            expansion={expansion}
                                            toggle={toggle}
                                        >
                                            <PrintState feed={feed} blockedCountSignal={blockedCountSignal} />
                                        </Protections>
                                    </SettingsProvider>
                                );
                            }}
                        </MockWithState>
                    </TubeGrid>
                    <h2>AdBlocking = "disabled"</h2>
                    <br />
                    <TubeGrid>
                        <MockWithState initial={0}>
                            {(/** @type {Mock} */ { expansion, feed, setFeed, blockedCountSignal, toggle }) => {
                                return (
                                    <Protections
                                        blockedCountSignal={blockedCountSignal}
                                        feed={feed}
                                        setFeed={setFeed}
                                        expansion={expansion}
                                        toggle={toggle}
                                    >
                                        <PrivacyStatsEmptyState />
                                    </Protections>
                                );
                            }}
                        </MockWithState>
                        <MockWithState initial={0} feedType={'activity'}>
                            {(/** @type {Mock} */ { expansion, feed, setFeed, blockedCountSignal, toggle }) => {
                                return (
                                    <Protections
                                        blockedCountSignal={blockedCountSignal}
                                        feed={feed}
                                        setFeed={setFeed}
                                        expansion={expansion}
                                        toggle={toggle}
                                    >
                                        <ActivityEmptyState />
                                    </Protections>
                                );
                            }}
                        </MockWithState>
                        <MockWithState initial={1}>
                            {(/** @type {Mock} */ { expansion, feed, setFeed, blockedCountSignal, toggle }) => {
                                return (
                                    <Protections
                                        blockedCountSignal={blockedCountSignal}
                                        feed={feed}
                                        setFeed={setFeed}
                                        expansion={expansion}
                                        toggle={toggle}
                                    >
                                        <PrintState feed={feed} blockedCountSignal={blockedCountSignal} />
                                    </Protections>
                                );
                            }}
                        </MockWithState>
                        <MockWithState initial={0} interval={1000}>
                            {(/** @type {Mock} */ { expansion, feed, setFeed, blockedCountSignal, toggle }) => {
                                return (
                                    <Protections
                                        blockedCountSignal={blockedCountSignal}
                                        feed={feed}
                                        setFeed={setFeed}
                                        expansion={expansion}
                                        toggle={toggle}
                                    >
                                        <PrintState feed={feed} blockedCountSignal={blockedCountSignal} />
                                    </Protections>
                                );
                            }}
                        </MockWithState>
                        <MockWithState initial={100} feedType={'activity'}>
                            {(/** @type {Mock} */ { expansion, feed, setFeed, blockedCountSignal, toggle }) => {
                                return (
                                    <Protections
                                        blockedCountSignal={blockedCountSignal}
                                        feed={feed}
                                        setFeed={setFeed}
                                        expansion={expansion}
                                        toggle={toggle}
                                    >
                                        <PrintState feed={feed} blockedCountSignal={blockedCountSignal} />
                                    </Protections>
                                );
                            }}
                        </MockWithState>
                    </TubeGrid>
                </Fragment>
            );
        },
    },
};

function PrintState(props) {
    return (
        <pre style={{ marginTop: '24px' }}>
            <code>
                {JSON.stringify(
                    {
                        feed: props.feed,
                        blockedCount: props.blockedCountSignal.value,
                    },
                    null,
                    2,
                )}
            </code>
        </pre>
    );
}

/**
 * @typedef {object} Mock
 * @property {() => void} toggle
 * @property {import('../../../types/new-tab.js').Expansion} expansion
 * @property {import('@preact/signals').Signal<number>} blockedCountSignal
 * @property {FeedType} feed
 * @property {(f: FeedType) => void} setFeed
 *
 * @param {object} props
 * @param {number} [props.initial=0]
 * @param {number} [props.interval=0]
 * @param {FeedType} [props.feedType]
 * @param {(mock: Mock) => import("preact").ComponentChild} props.children
 */
const MockWithState = ({ children, initial = 0, feedType = 'privacy-stats', interval = 0 }) => {
    const [feed, setFeed] = useState(feedType);
    const [expansion, setExpansion] = useState(/** @type {import('../../../types/new-tab.js').Expansion} */ ('expanded'));
    const signal = useSignal(initial);
    useEffect(() => {
        if (interval === 0) return;
        const int = setInterval(() => (signal.value += 1), interval);
        return () => clearInterval(int);
    }, [interval]);
    const toggle = () => {
        setExpansion((old) => (old === 'expanded' ? 'collapsed' : 'expanded'));
    };
    return children({ toggle, expansion, feed, setFeed, blockedCountSignal: signal });
};
