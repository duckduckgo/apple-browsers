/**
 * @typedef {import("../../types/new-tab.js").WidgetConfigs} WidgetConfigs
 */
import { Service } from '../service.js';

export class WidgetConfigService {
    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed
     * @param {WidgetConfigs} initialConfig
     * @internal
     */
    constructor(ntp, initialConfig) {
        /**
         * @type {Service<WidgetConfigs>}
         * @internal
         */
        this.service = new Service(
            {
                subscribe: (cb) => ntp.messaging.subscribe('widgets_onConfigUpdated', cb),
                persist: (data) => ntp.messaging.notify('widgets_setConfig', data),
            },
            initialConfig,
        );
    }

    /**
     * @param {(evt: {data: WidgetConfigs, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onData(cb) {
        return this.service.onData(cb);
    }

    /**
     * Set the visibility of a widget.
     *
     * Note: This will persist
     *
     * @param {string} id - the widget ID to toggle.
     * @internal
     */
    toggleVisibility(id) {
        this.service.update((old) => {
            return old.map((widgetConfigItem) => {
                if (widgetConfigItem.id === id) {
                    const alt =
                        widgetConfigItem.visibility === 'visible' ? /** @type {const} */ ('hidden') : /** @type {const} */ ('visible');
                    return { ...widgetConfigItem, visibility: alt };
                }
                return widgetConfigItem;
            });
        });
    }
}
