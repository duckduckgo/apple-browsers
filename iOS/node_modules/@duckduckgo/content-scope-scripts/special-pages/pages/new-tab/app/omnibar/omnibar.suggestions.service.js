/**
 * @typedef {import("../../types/new-tab.js").SuggestionsData} SuggestionsData
 */

const EVENT_DATA = 'data';

export class OmnibarSuggestionsService {
    #eventTarget = new EventTarget();
    #lastFetchId = 0;

    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed, expected to have a `subscribe` method.
     * @internal
     */
    constructor(ntp) {
        this.ntp = ntp;
    }

    /**
     * @param {string} term
     * @returns {Promise<SuggestionsData>}
     */
    triggerFetch(term) {
        const fetchId = ++this.#lastFetchId;
        const fetch = async () => {
            const data = await this.ntp.messaging.request('omnibar_getSuggestions', { term });
            if (fetchId === this.#lastFetchId) {
                this.#eventTarget.dispatchEvent(new CustomEvent(EVENT_DATA, { detail: { data, term } }));
            }
            return data;
        };
        return fetch();
    }

    /**
     * @param {(data: SuggestionsData, term: string) => void} cb
     * @returns {() => void}
     */
    onData(cb) {
        /** @type {(event: CustomEvent<{data: SuggestionsData, term: string}>) => void} */
        const handler = (event) => cb(event.detail.data, event.detail.term);
        this.#eventTarget.addEventListener(EVENT_DATA, handler);
        return () => this.#eventTarget.removeEventListener(EVENT_DATA, handler);
    }
}
