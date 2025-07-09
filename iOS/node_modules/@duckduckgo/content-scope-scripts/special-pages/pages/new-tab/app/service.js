/**
 * @typedef {'initial' | 'subscription' | 'manual' | 'trigger-fetch'} InvocationSource
 */
/**
 * @template Data - the data format this service produces/stores
 *
 * This implements a 'last push wins' strategy for
 * persisting UI state. user-initiated events will be debounced, only
 * taking the last action. These will update the internal/in-memory state
 * immediately (offering instant updates), and then will try to persist it.
 *
 * If a subscription event arrives during the debounced
 * period, it is always respected, and the local sync value will be overwritten.
 *
 */
export class Service {
    eventTarget = new EventTarget();
    DEBOUNCE_TIME_MS = 200;
    _broadcast = true;
    /** @type {undefined|((old: Data, next: Data, trigger: InvocationSource) => Data)} */
    accept;
    /**
     * @param {object} props
     * @param {(arg?: any) => Promise<Data>} [props.initial]
     * @param {(fn: (t: Data) => void) => () => void} [props.subscribe] - optional subscribe
     * @param {(t: Data) => void} [props.persist] - optional persist method
     * @param {(old: Data, next: Data) => Data} [props.update] - optional updater
     * @param {Data|null} [initial] - optional initial data
     */
    constructor(props, initial) {
        this.impl = props;

        if (initial) {
            this.data = initial;
        } else {
            this.data = null;
        }
    }

    /**
     * @param {(old: Data, next: Data, trigger: InvocationSource) => Data} fn
     */
    withUpdater(fn) {
        this.accept = fn;
        return this;
    }

    /**
     * @param {any} [params]
     * @return {Promise<Data>}
     */
    async fetchInitial(params) {
        if (!this.impl.initial) throw new Error('unreachable');
        const initial = await this.impl.initial(params);
        this._accept(initial, 'initial');
        return /** @type {Data} */ (this.data);
    }

    /**
     * @param {any} [params]
     * @return {Promise<Data>}
     */
    async triggerFetch(params) {
        if (!this.impl.initial) throw new Error('unreachable');
        const next = await this.impl.initial(params);
        this._accept(next, 'trigger-fetch');
        return /** @type {Data} */ (this.data);
    }

    /**
     * This is convenience to prevent the boilerplate of dealing with the
     * eventTarget directly.
     *
     * Consumers pass a callback, which will be invoked with Data and the Source.
     *
     * A function is returned, which can be used to remove the event listener
     *
     * @param {(evt: {data: Data, source: InvocationSource}) => void} cb
     */
    onData(cb) {
        this._setupSubscription();
        const controller = new AbortController();
        this.eventTarget.addEventListener(
            'data',
            (/** @type {CustomEvent<{data: Data, source: InvocationSource}>} */ evt) => {
                cb(evt.detail);
            },
            { signal: controller.signal },
        );
        return () => controller.abort();
    }

    /**
     * Remove data subscriptions
     */
    destroy() {
        this.sub?.();
    }

    /**
     * Setup the subscription if one doesn't already exist
     * @private
     */
    _setupSubscription() {
        if (this.sub) return;
        this.sub = this.impl.subscribe?.((data) => {
            this._accept(data, 'subscription');
        });
    }

    disableBroadcast() {
        this._broadcast = false;
    }

    enableBroadcast() {
        this._broadcast = true;
    }

    flush() {
        if (this.data) this._accept(this.data, 'manual');
    }

    /**
     * Apply a function over the current state.
     *
     * The change will be broadcast to observers immediately,
     * and then persists after a debounced period.
     *
     * @param {(prev: Data) => Data} updaterFn - the function that returns the next state
     */
    update(updaterFn) {
        if (this.data === null) return;
        const next = updaterFn(this.data);
        if (next) {
            this._accept(next, 'manual');
        } else {
            console.warn('could not update');
        }
    }
    /**
     * @param {Data} data
     * @param {InvocationSource} source
     * @private
     */
    _accept(data, source) {
        if (this.accept && source !== 'initial') {
            this.data = /** @type {NonNullable<Data>} */ (this.accept(/** @type {NonNullable<Data>} */ (this.data), data, source));
        } else {
            this.data = /** @type {NonNullable<Data>} */ (data);
        }

        // do nothing when it's the initial data
        if (source === 'initial') return;

        // always cancel any existing debounced timers
        this.clearDebounceTimer();

        if (!this._broadcast) return console.warn('not broadcasting');

        // always broadcast the change on the event target
        const dataEvent = new CustomEvent('data', {
            detail: {
                data: this.data,
                source,
            },
        });
        this.eventTarget.dispatchEvent(dataEvent);

        // try to persist if the last try was 'manual' update
        if (source === 'manual') {
            const time = window.location.search.includes('p2') ? this.DEBOUNCE_TIME_MS * 20.5 : this.DEBOUNCE_TIME_MS;
            this.debounceTimer = setTimeout(() => {
                this.persist();
            }, time);
        }
    }

    /**
     * Clears the debounce timer if it exists, simulating the switchMap behavior.
     */
    clearDebounceTimer() {
        if (this.debounceTimer) {
            clearTimeout(this.debounceTimer);
            this.debounceTimer = null;
        }
    }

    /**
     * Persists the current in-memory widget configuration state to the internal data feed.
     */
    persist() {
        // some services will not implement persistence
        if (!this.impl.persist) return;

        // if the data was never set, there's nothing to persist
        if (this.data === null) return;

        // send the data
        this.impl.persist(this.data);
    }
}
