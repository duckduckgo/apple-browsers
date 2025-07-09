import { useCallback, useEffect, useReducer, useState } from 'preact/hooks';
import { h } from 'preact';
import { PrivacyStatsContext, PrivacyStatsDispatchContext } from '../components/PrivacyStatsProvider.js';
import { privacyStatsMocks } from './privacy-stats.mocks.js';
import { reducer } from '../../service.hooks.js';
import { BodyExpansionContext, BodyExpansionApiContext } from '../components/BodyExpansionProvider.js';

/**
 * @typedef {import('../../../types/new-tab').TrackerCompany} TrackerCompany
 * @typedef {import('../../../types/new-tab').Expansion} Expansion
 * @typedef {import('../../../types/new-tab').PrivacyStatsData} PrivacyStatsData
 * @typedef {import('../../service.hooks.js').State<PrivacyStatsData, null>} State
 * @typedef {import('../../service.hooks.js').Events<PrivacyStatsData, null>} Events
 */

/**
 * A provider used in storybook-like situations: it just returns a static set of
 * data + a toggle function.
 *
 * @param {Object} props - The props object containing the data.
 * @param {import("preact").ComponentChild} [props.children] - The children elements to be rendered.
 * @param {Expansion} [props.bodyExpansion]
 * @param {PrivacyStatsData} [props.data]
 * @param {boolean} [props.ticker] - if true, gradually increment the count of the first company, for testing
 *
 */

export function PrivacyStatsMockProvider({ data = privacyStatsMocks.few, ticker = false, children }) {
    const initial = /** @type {import('../components/PrivacyStatsProvider.js').State} */ ({
        status: 'ready',
        data,
        config: null,
    });

    /** @type {[State, import('preact/hooks').Dispatch<Events>]} */
    const [state, send] = useReducer(reducer, initial);

    useEffect(() => {
        if (!ticker) return;
        if (state.status === 'ready') {
            const next = {
                trackerCompanies: state.data.trackerCompanies.map((company, index) => {
                    if (index === 0) return { ...company, count: company.count + 1 };
                    return company;
                }),
            };
            const time = setTimeout(() => {
                send({ kind: 'data', data: next });
            }, 1000);
            return () => clearTimeout(time);
        }
        return () => {};
    }, [ticker]);

    return (
        <PrivacyStatsContext.Provider value={{ state }}>
            <PrivacyStatsDispatchContext.Provider value={send}>
                <BodyExpansionMockProvider>{children}</BodyExpansionMockProvider>
            </PrivacyStatsDispatchContext.Provider>
        </PrivacyStatsContext.Provider>
    );
}

/**
 * @param {Object} props - The props object containing the data.
 * @param {import("preact").ComponentChild} [props.children] - The children elements to be rendered.
 * @param {Expansion} [props.bodyExpansion]
 */
export function BodyExpansionMockProvider({ children, bodyExpansion = 'collapsed' }) {
    const [bodyExpansionState, setBodyExpansion] = useState(bodyExpansion);
    const showMore = useCallback(() => {
        setBodyExpansion('expanded');
    }, []);
    const showLess = useCallback(() => {
        setBodyExpansion('collapsed');
    }, []);
    return (
        <BodyExpansionContext.Provider value={bodyExpansionState}>
            <BodyExpansionApiContext.Provider value={{ showMore, showLess }}>{children}</BodyExpansionApiContext.Provider>
        </BodyExpansionContext.Provider>
    );
}
