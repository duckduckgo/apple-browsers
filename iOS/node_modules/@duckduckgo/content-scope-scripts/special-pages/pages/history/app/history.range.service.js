/**
 * @typedef {import('../types/history.js').Range} Range
 * @typedef {import('../types/history.js').RangeId} RangeId
 * @typedef {{ranges: Range[]}} RangeData
 * @typedef {{kind: 'none'} | { kind: 'domain-search'; value: string }} MenuContinuation
 */

export class HistoryRangeService {
    static REFRESH_EVENT = 'refresh';
    static DATA_EVENT = 'data';
    index = 0;
    internal = new EventTarget();
    dataReadinessSignal = new EventTarget();

    /**
     * @type {RangeData|null}
     */
    ranges = null;

    /**
     * @param {import("../src/index.js").HistoryPage} history
     */
    constructor(history) {
        this.history = history;

        this.internal.addEventListener(HistoryRangeService.REFRESH_EVENT, () => {
            // increment the counter
            this.index++;
            // and, store a local index, we can check it when the promise resolves
            const index = this.index;

            this.fetcher().then((next) => {
                /**
                 * First, reject overlapping promises
                 */
                const resolvedPromiseIsStale = this.index !== index;
                if (resolvedPromiseIsStale) return console.log('❌ rejected stale result');
                this.accept(next);
            });
        });
    }

    /**
     * @param {RangeData} d
     */
    accept(d) {
        this.ranges = d;
        this.dataReadinessSignal.dispatchEvent(new Event(HistoryRangeService.DATA_EVENT));
    }

    fetcher() {
        console.log(`🦻 [getRanges]`);
        return this.history.messaging.request('getRanges');
    }

    /**
     * @returns {Promise<RangeData>}
     */
    async getInitial() {
        const rangesPromise = await this.fetcher();
        this.accept(rangesPromise);
        return rangesPromise;
    }

    refresh() {
        this.internal.dispatchEvent(new Event(HistoryRangeService.REFRESH_EVENT));
    }

    /**
     * @param {(data: RangeData) => void} cb
     */
    onResults(cb) {
        const controller = new AbortController();
        this.dataReadinessSignal.addEventListener(
            HistoryRangeService.DATA_EVENT,
            () => {
                if (this.ranges === null) throw new Error('unreachable');
                cb(this.ranges);
            },
            { signal: controller.signal },
        );
        return () => controller.abort();
    }

    /**
     * @param {RangeId} range
     */
    async deleteRange(range) {
        console.log('📤 [deleteRange]: ', JSON.stringify({ range }));
        return await this.history.messaging.request('deleteRange', { range });
    }
}
