/* eslint-disable promise/prefer-await-to-then */
import { createContext, h } from 'preact';
import { paramsToQuery, toRange } from '../../history.service.js';
import { useCallback, useContext } from 'preact/hooks';
import { useQueryDispatch } from './QueryProvider.js';
import { signal, useSignal, useSignalEffect } from '@preact/signals';
import { generateHeights, generateViewIds } from '../../utils.js';

/**
 * @typedef {import('../../../types/history.ts').HistoryQueryInfo} HistoryQueryInfo
 * @typedef {import('../../../types/history.ts').HistoryQuery['source']} Source
 * @typedef {{kind: 'search-commit', params: URLSearchParams, source: Source}
 * | {kind: 'delete-range'; value: string }
 * | {kind: 'delete-all'; }
 * | {kind: 'delete-term'; term: string }
 * | {kind: 'delete-domain'; domain: string }
 * | {kind: 'delete-entries-by-index'; value: number[] }
 * | {kind: 'open-url'; url: string, target: 'new-tab' | 'new-window' | 'same-tab' }
 * | {kind: 'show-entries-menu'; indexes: number[] }
 * | {kind: 'request-more'; end: number }
 * } Action
 */

/**
 * @param {Action} action
 */
function defaultDispatch(action) {
    console.log('would dispatch', action);
}
const HistoryServiceDispatchContext = createContext(defaultDispatch);

/**
 * @typedef {object} Results
 * @property {import('../../../types/history.ts').HistoryItem[]} items
 * @property {number[]} heights
 * @property {string[]} viewIds
 * @property {HistoryQueryInfo} info
 */
/**
 * @typedef {import('../../../types/history.ts').Range} Range
 * @import { ReadonlySignal } from '@preact/signals'
 */

const ResultsContext = createContext(
    /** @type {ReadonlySignal<Results>} */ (
        signal({
            items: [],
            heights: [],
            viewIds: [],
            info: { finished: false, query: { term: '' } },
        })
    ),
);
const RangesContext = createContext(/** @type {ReadonlySignal<Range[]>} */ (signal([])));

/**
 * Provides a context for the history service, allowing dependent components to access it.
 * Everything that interacts with the service should be registered here
 *
 * @param {Object} props
 * @param {import("../../history.service.js").HistoryService} props.service
 * @param {import('../../history.service.js').InitialServiceData} props.initial - The initial state data for the history service.
 * @param {import("preact").ComponentChild} props.children
 */
export function HistoryServiceProvider({ service, children, initial }) {
    const queryDispatch = useQueryDispatch();
    const ranges = useSignal(initial.ranges.ranges);
    const results = useSignal({
        info: initial.query.info,
        items: initial.query.results,
        heights: generateHeights(initial.query.results),
        viewIds: generateViewIds(initial.query.results),
    });

    useSignalEffect(() => {
        const unsub = service.onResults((data) => {
            results.value = {
                items: data.results,
                info: data.info,
                heights: generateHeights(data.results),
                viewIds: generateViewIds(data.results),
            };
        });

        // Subscribe to changes in the 'ranges' data and reflect the updates into the UI
        const unsubRanges = service.onRanges((data) => {
            ranges.value = data.ranges;
        });
        return () => {
            unsub();
            unsubRanges();
        };
    });

    /**
     * @param {Action} action
     */
    function dispatch(action) {
        switch (action.kind) {
            case 'search-commit': {
                const asQuery = paramsToQuery(action.params, action.source);
                service.trigger(asQuery);
                break;
            }
            case 'delete-range': {
                const range = toRange(action.value);
                if (range) {
                    service
                        .deleteRange(range)
                        .then((resp) => {
                            if (resp.kind === 'delete') {
                                queryDispatch({ kind: 'reset' });
                                service.refreshRanges();
                            }
                        })
                        .catch(console.error);
                }
                break;
            }
            case 'delete-domain': {
                service
                    .deleteDomain(action.domain)
                    .then((resp) => {
                        if (resp.kind === 'delete') {
                            queryDispatch({ kind: 'reset' });
                            service.refreshRanges();
                        }
                    })
                    .catch(console.error);
                break;
            }
            case 'delete-entries-by-index': {
                service
                    .entriesDelete(action.value)
                    .then((resp) => {
                        if (resp.kind === 'delete') {
                            service.refreshRanges();
                        }
                    })
                    .catch(console.error);
                break;
            }
            case 'delete-all': {
                service
                    .deleteRange('all')
                    .then((x) => {
                        if (x.kind === 'delete') {
                            service.refreshRanges();
                        }
                    })
                    .catch(console.error);
                break;
            }
            case 'delete-term': {
                service
                    .deleteTerm(action.term)
                    .then((resp) => {
                        if (resp.kind === 'delete') {
                            queryDispatch({ kind: 'reset' });
                            service.refreshRanges();
                        }
                    })
                    .catch(console.error);
                break;
            }
            case 'open-url': {
                service.openUrl(action.url, action.target);
                break;
            }
            case 'show-entries-menu': {
                service
                    .entriesMenu(action.indexes)
                    .then((resp) => {
                        if (resp.kind === 'domain-search' && 'value' in resp) {
                            queryDispatch({ kind: 'search-by-domain', value: resp.value });
                        } else if (resp.kind === 'delete') {
                            service.refreshRanges();
                        }
                    })
                    .catch(console.error);
                break;
            }
            case 'request-more': {
                service.requestMore(action.end);
                break;
            }
        }
    }

    const dispatcher = useCallback(dispatch, [service]);

    return (
        <HistoryServiceDispatchContext.Provider value={dispatcher}>
            <RangesContext.Provider value={ranges}>
                <ResultsContext.Provider value={results}>{children}</ResultsContext.Provider>
            </RangesContext.Provider>
        </HistoryServiceDispatchContext.Provider>
    );
}

export function useHistoryServiceDispatch() {
    return useContext(HistoryServiceDispatchContext);
}

// Hook for consuming the context
export function useResultsData() {
    return useContext(ResultsContext);
}

// Hook for consuming the context
export function useRangesData() {
    return useContext(RangesContext);
}
