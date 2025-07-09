import { Service } from '../service.js';

/**
 * @typedef {import("../../types/new-tab.js").FavoritesData} FavoritesData
 * @typedef {import("../../types/new-tab.js").Favorite} Favorite
 * @typedef {import("../../types/new-tab.js").FavoritesConfig} FavoritesConfig
 * @typedef {import("../../types/new-tab.js").FavoritesOpenAction} FavoritesOpenAction
 */

export class FavoritesService {
    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed, expected to have a `subscribe` method.
     * @internal
     */
    constructor(ntp) {
        this.ntp = ntp;

        /** @type {Service<FavoritesData>} */
        this.dataService = new Service({
            initial: () => ntp.messaging.request('favorites_getData'),
            subscribe: (cb) => ntp.messaging.subscribe('favorites_onDataUpdate', cb),
        });

        /** @type {Service<FavoritesConfig>} */
        this.configService = new Service({
            initial: () => ntp.messaging.request('favorites_getConfig'),
            subscribe: (cb) => ntp.messaging.subscribe('favorites_onConfigUpdate', cb),
            persist: (data) => ntp.messaging.notify('favorites_setConfig', data),
        });
    }

    name() {
        return 'FavoritesService';
    }

    /**
     * @returns {Promise<{data: FavoritesData; config: FavoritesConfig}>}
     * @internal
     */
    async getInitial() {
        const p1 = this.configService.fetchInitial();
        const p2 = this.dataService.fetchInitial();
        const [config, data] = await Promise.all([p1, p2]);
        return { config, data };
    }

    /**
     * @internal
     */
    destroy() {
        this.configService.destroy();
        this.dataService.destroy();
    }

    /**
     * @param {(evt: {data: FavoritesData, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onData(cb) {
        return this.dataService.onData(cb);
    }

    /**
     * @param {(evt: {data: FavoritesConfig, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onConfig(cb) {
        return this.configService.onData(cb);
    }

    onFaviconsRefreshed(cb) {
        return this.ntp.messaging.subscribe('favorites_onRefresh', (data) => {
            if (data.items.some((item) => item.kind === 'favicons')) {
                cb();
            }
        });
    }

    /**
     * Update the in-memory data immediate and persist.
     * Any state changes will be broadcast to consumers synchronously
     * @internal
     */
    toggleExpansion() {
        this.configService.update((old) => {
            if (old.expansion === 'expanded') {
                return { ...old, expansion: /** @type {const} */ ('collapsed') };
            } else {
                return { ...old, expansion: /** @type {const} */ ('expanded') };
            }
        });
    }

    /**
     * @param {FavoritesData} data
     * @param {string} id - entity id to move
     * @param {number} targetIndex - target index
     * @param {number} fromIndex - from index
     * @internal
     */
    setFavoritesOrder(data, id, fromIndex, targetIndex) {
        // update in memory instantly - this will broadcast changes to all listeners

        this.dataService.update((_old) => {
            return data;
        });

        // then let the native side know about it
        this.ntp.messaging.notify('favorites_move', {
            id,
            targetIndex,
            fromIndex,
        });
    }

    /**
     * @param {string} id - entity id
     * @internal
     */
    openContextMenu(id) {
        // let the native side know too
        this.ntp.messaging.notify('favorites_openContextMenu', { id });
    }

    /**
     * @param {string} id - entity id
     * @param {string} url - target url
     * @param {FavoritesOpenAction['target']} target
     * @internal
     */
    openFavorite(id, url, target) {
        // let the native side know too
        this.ntp.messaging.notify('favorites_open', { id, url, target });
    }

    /**
     * @internal
     */
    add() {
        this.ntp.messaging.notify('favorites_add');
    }
}
