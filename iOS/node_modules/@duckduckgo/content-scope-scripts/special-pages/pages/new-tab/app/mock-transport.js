import { TestTransportConfig } from '@duckduckgo/messaging';

import { privacyStatsMocks } from './privacy-stats/mocks/privacy-stats.mocks.js';
import { rmfDataExamples } from './remote-messaging-framework/mocks/rmf.data.js';
import { favorites, gen } from './favorites/mocks/favorites.data.js';
import { updateNotificationExamples } from './update-notification/mocks/update-notification.data.js';
import { variants as nextSteps } from './next-steps/nextsteps.data.js';
import { customizerData, customizerMockTransport } from './customizer/mocks.js';
import { freemiumPIRDataExamples } from './freemium-pir-banner/mocks/freemiumPIRBanner.data.js';
import { activityMockTransport } from './activity/mocks/activity.mock-transport.js';
import { protectionsMockTransport } from './protections/mocks/protections.mock-transport.js';
import { omnibarMockTransport } from './omnibar/mocks/omnibar.mock-transport.js';

/**
 * @typedef {import('../types/new-tab').Favorite} Favorite
 * @typedef {import('../types/new-tab').FavoritesData} FavoritesData
 * @typedef {import('../types/new-tab').FavoritesConfig} FavoritesConfig
 * @typedef {import('../types/new-tab').NextStepsConfig} NextStepsConfig
 * @typedef {import('../types/new-tab').NextStepsCards} NextStepsCards
 * @typedef {import('../types/new-tab').NextStepsData} NextStepsData
 * @typedef {import('../types/new-tab').UpdateNotificationData} UpdateNotificationData
 * @typedef {import('../types/new-tab').NewTabPageSettings} NewTabPageSettings
 * @typedef {import('../types/new-tab').NewTabMessages['subscriptions']['subscriptionEvent']} SubscriptionNames
 * @typedef {import('@duckduckgo/messaging/lib/test-utils.mjs').SubscriptionEvent} SubscriptionEvent
 */

const VERSION_PREFIX = '__ntp_31__.';
const url = new URL(window.location.href);

export function mockTransport() {
    let channel;

    if (typeof globalThis.BroadcastChannel !== 'undefined') {
        channel = new BroadcastChannel('ntp');
    }

    /** @type {Map<string, (d: any)=>void>} */
    const subscriptions = new Map();
    if ('__playwright_01' in window) {
        window.__playwright_01.publishSubscriptionEvent = (/** @type {SubscriptionEvent} */ evt) => {
            const matchingCallback = subscriptions.get(evt.subscriptionName);
            if (!matchingCallback) return console.error('no matching callback for subscription', evt);
            matchingCallback(evt.params);
        };
    }

    function broadcast(named) {
        setTimeout(() => {
            channel?.postMessage({
                change: named,
            });
        }, 100);
    }

    /**
     * @param {string} name
     * @return {any}
     */
    function read(name) {
        // console.log('*will* read from LS', name)
        try {
            if (url.searchParams.has('skip-read')) {
                console.warn('not reading from localstorage, because skip-read was in the search');
                return null;
            }
            const item = localStorage.getItem(VERSION_PREFIX + name);
            if (!item) return null;
            // console.log('did read from LS', item)
            return JSON.parse(item);
        } catch (e) {
            console.error('Failed to parse initialSetup from localStorage', e);
            return null;
        }
    }

    /**
     * @param {string} name
     * @param {Record<string, any>} value
     */
    function write(name, value) {
        try {
            if (url.searchParams.has('skip-write')) {
                console.warn('not writing to localstorage, because skip-write was in the search');
                return;
            }
            localStorage.setItem(VERSION_PREFIX + name, JSON.stringify(value));
            // console.log('✅ did write')
        } catch (e) {
            console.error('Failed to write', e);
        }
    }

    /** @type {Map<SubscriptionNames, any[]>} */
    const rmfSubscriptions = new Map();
    const freemiumPIRBannerSubscriptions = new Map();
    const nextStepsSubscriptions = new Map();

    function clearRmf() {
        const listeners = rmfSubscriptions.get('rmf_onDataUpdate') || [];
        /** @type {import('../types/new-tab.ts').RMFData} */
        const message = { content: undefined };
        for (const listener of listeners) {
            listener(message);
        }
    }

    function clearNextStepsCard(cardId, data) {
        const listeners = nextStepsSubscriptions.get('nextSteps_onDataUpdate') || [];
        const newContent = data.content.filter((card) => card.id !== cardId);
        const message = { content: newContent };
        for (const listener of listeners) {
            listener(message);
            write('nextSteps_data', message);
        }
    }

    const transports = {
        customizer: customizerMockTransport(),
        activity: activityMockTransport(),
        protections: protectionsMockTransport(),
        omnibar: omnibarMockTransport(),
    };

    return new TestTransportConfig({
        notify(_msg) {
            window.__playwright_01?.mocks?.outgoing?.push?.({ payload: structuredClone(_msg) });
            /** @type {import('../types/new-tab.ts').NewTabMessages['notifications']} */
            const msg = /** @type {any} */ (_msg);
            const [namespace] = msg.method.split('_');
            if (namespace in transports) {
                transports[namespace]?.impl.notify(_msg);
                return;
            }
            switch (msg.method) {
                case 'widgets_setConfig': {
                    if (!msg.params) throw new Error('unreachable');
                    write('widget_config', msg.params);
                    broadcast('widget_config');
                    return;
                }
                case 'rmf_primaryAction': {
                    console.log('ignoring rmf_primaryAction', msg.params);
                    clearRmf();
                    return;
                }
                case 'rmf_secondaryAction': {
                    console.log('ignoring rmf_secondaryAction', msg.params);
                    clearRmf();
                    return;
                }
                case 'rmf_dismiss': {
                    console.log('ignoring rmf_dismiss', msg.params);
                    clearRmf();
                    return;
                }
                case 'freemiumPIRBanner_action': {
                    console.log('ignoring freemiumPIRBanner_action', msg.params);
                    return;
                }
                case 'freemiumPIRBanner_dismiss': {
                    console.log('ignoring freemiumPIRBanner_dismiss', msg.params);
                    return;
                }
                case 'favorites_setConfig': {
                    if (!msg.params) throw new Error('unreachable');

                    const { animation, ...rest } = msg.params;
                    write('favorites_config', rest);
                    broadcast('favorites_config');
                    return;
                }
                case 'favorites_move': {
                    if (!msg.params) throw new Error('unreachable');
                    const { id, targetIndex } = msg.params;
                    const data = read('favorites_data');

                    if (Array.isArray(data?.favorites)) {
                        const favorites = reorderArray(data.favorites, id, targetIndex);
                        write('favorites_data', { favorites });
                        broadcast('favorites_data');
                    }

                    return;
                }
                case 'favorites_openContextMenu': {
                    if (!msg.params) throw new Error('unreachable');
                    console.log('mock: ignoring favorites_openContextMenu', msg.params);
                    return;
                }
                case 'favorites_add': {
                    console.log('mock: ignoring favorites_add');
                    return;
                }
                case 'nextSteps_dismiss': {
                    if (msg.params.id) {
                        const data = read('nextSteps_data');
                        clearNextStepsCard(msg.params.id, data);
                        return;
                    }
                    console.log('ignoring nextSteps_dismiss');
                    return;
                }
                default: {
                    console.warn('unhandled notification', msg);
                }
            }
        },
        subscribe(_msg, cb) {
            /** @type {import('../types/new-tab.ts').NewTabMessages['subscriptions']['subscriptionEvent']} */
            const sub = /** @type {any} */ (_msg.subscriptionName);

            if ('__playwright_01' in window) {
                window.__playwright_01?.mocks?.outgoing?.push?.({ payload: structuredClone(_msg) });
                subscriptions.set(sub, cb);
                return () => {
                    subscriptions.delete(sub);
                };
            }

            const [namespace] = sub.split('_');
            if (namespace in transports) {
                return transports[namespace]?.impl.subscribe(_msg, cb);
            }

            switch (sub) {
                case 'widgets_onConfigUpdated': {
                    const controller = new AbortController();
                    channel?.addEventListener(
                        'message',
                        (msg) => {
                            if (msg.data.change === 'widget_config') {
                                const values = read('widget_config');
                                if (values) {
                                    cb(values);
                                }
                            }
                        },
                        { signal: controller.signal },
                    );
                    return () => controller.abort();
                }
                case 'freemiumPIRBanner_onDataUpdate': {
                    // store the callback for later (eg: dismiss)
                    const prev = freemiumPIRBannerSubscriptions.get('freemiumPIRBanner_onDataUpdate') || [];
                    const next = [...prev];
                    next.push(cb);
                    freemiumPIRBannerSubscriptions.set('freemiumPIRBanner_onDataUpdate', next);

                    const freemiumPIRBannerParam = url.searchParams.get('pir');

                    if (freemiumPIRBannerParam !== null && freemiumPIRBannerParam in freemiumPIRDataExamples) {
                        const message = freemiumPIRDataExamples[freemiumPIRBannerParam];
                        cb(message);
                    }
                    return () => {};
                }
                case 'nextSteps_onDataUpdate': {
                    const prev = nextStepsSubscriptions.get('nextSteps_onDataUpdate') || [];
                    const next = [...prev];
                    next.push(cb);
                    nextStepsSubscriptions.set('nextSteps_onDataUpdate', next);
                    const params = url.searchParams.get('next-steps');
                    if (params && params in nextSteps) {
                        const data = read('nextSteps_data');
                        cb(data);
                    }

                    return () => {};
                }
                case 'rmf_onDataUpdate': {
                    // store the callback for later (eg: dismiss)
                    const prev = rmfSubscriptions.get('rmf_onDataUpdate') || [];
                    const next = [...prev];
                    next.push(cb);
                    rmfSubscriptions.set('rmf_onDataUpdate', next);

                    const delay = url.searchParams.get('rmf-delay');
                    const rmfParam = url.searchParams.get('rmf');

                    if (delay !== null && rmfParam !== null && rmfParam in rmfDataExamples) {
                        const ms = parseInt(delay, 10);
                        const timeout = setTimeout(() => {
                            const message = rmfDataExamples[rmfParam];
                            cb(message);
                        }, ms);
                        return () => clearTimeout(timeout);
                    }
                    return () => {};
                }
                case 'updateNotification_onDataUpdate': {
                    const update = url.searchParams.get('update-notification');
                    const delay = url.searchParams.get('update-notification-delay');
                    if (update && delay && update in updateNotificationExamples) {
                        const ms = parseInt(delay, 10);
                        const timeout = setTimeout(() => {
                            const message = updateNotificationExamples[update];
                            cb(message);
                        }, ms);
                        return () => clearTimeout(timeout);
                    }
                    return () => {};
                }
                case 'favorites_onDataUpdate': {
                    const controller = new AbortController();
                    channel?.addEventListener(
                        'message',
                        (msg) => {
                            if (msg.data.change === 'favorites_data') {
                                const values = read('favorites_data');
                                if (values) {
                                    cb(values);
                                }
                            }
                        },
                        { signal: controller.signal },
                    );

                    return () => controller.abort();
                }
                case 'stats_onDataUpdate': {
                    const statsVariant = url.searchParams.get('stats');
                    const count = url.searchParams.get('stats-update-count');
                    const updateMaxCount = parseInt(count || '0');
                    if (updateMaxCount === 0) return () => {};
                    if (statsVariant === 'willUpdate') {
                        let inc = 1;
                        const max = Math.min(updateMaxCount, 10);
                        const int = setInterval(() => {
                            if (inc === max) return clearInterval(int);
                            const next = {
                                ...privacyStatsMocks.few,
                                trackerCompanies: privacyStatsMocks.few.trackerCompanies.map((x, index) => {
                                    return {
                                        ...x,
                                        count: x.count + inc * index,
                                    };
                                }),
                            };
                            cb(next);
                            inc++;
                        }, 500);
                        return () => {
                            clearInterval(int);
                        };
                    } else if (statsVariant === 'growing') {
                        const list = privacyStatsMocks.many.trackerCompanies;
                        let index = 0;
                        const max = Math.min(updateMaxCount, list.length);
                        const int = setInterval(() => {
                            if (index === max) return clearInterval(int);
                            console.log({ index, max });
                            cb({
                                trackerCompanies: list.slice(0, index + 1),
                            });
                            index++;
                        }, 200);
                        return () => {};
                    } else {
                        console.log(statsVariant);
                        return () => {};
                    }
                }
                case 'favorites_onConfigUpdate': {
                    const controller = new AbortController();
                    channel?.addEventListener(
                        'message',
                        (msg) => {
                            if (msg.data.change === 'favorites_config') {
                                const values = read('favorites_config');
                                if (values) {
                                    cb(values);
                                }
                            }
                        },
                        { signal: controller.signal },
                    );
                    return () => controller.abort();
                }
                case 'favorites_onRefresh': {
                    if (url.searchParams.get('favoriteRefresh') === 'favicons') {
                        const timer = setTimeout(() => {
                            /** @type {import('../types/new-tab').FavoritesRefresh} */
                            const payload = {
                                items: [{ kind: 'favicons' }],
                            };
                            cb(payload);
                        }, 1000);
                        return () => {
                            clearTimeout(timer);
                        };
                    } else {
                        return () => {};
                    }
                }
            }
            return () => {};
        },
        // eslint-ignore-next-line require-await
        request(_msg) {
            window.__playwright_01?.mocks?.outgoing?.push?.({ payload: structuredClone(_msg) });
            /** @type {import('../types/new-tab.ts').NewTabMessages['requests']} */
            const msg = /** @type {any} */ (_msg);

            const [namespace] = msg.method.split('_');
            if (namespace in transports) {
                return transports[namespace]?.impl.request(_msg);
            }

            switch (msg.method) {
                case 'stats_getData': {
                    const statsVariant = url.searchParams.get('stats');
                    if (statsVariant && statsVariant in privacyStatsMocks) {
                        return Promise.resolve(privacyStatsMocks[statsVariant]);
                    }
                    return Promise.resolve(privacyStatsMocks.few);
                }
                case 'nextSteps_getConfig': {
                    /** @type {NextStepsConfig} */
                    const config = { expansion: 'collapsed' };
                    return Promise.resolve(config);
                }
                case 'nextSteps_getData': {
                    /** @type {NextStepsData} */
                    let data = { content: null };
                    const ids = url.searchParams.getAll('next-steps');
                    if (ids.length) {
                        /** @type {NextStepsData} */
                        data = {
                            content: ids
                                .filter((id) => {
                                    if (!(id in nextSteps)) {
                                        console.warn(`${id} missing in nextSteps data`);
                                        return false;
                                    }
                                    return true;
                                })
                                .map((id) => {
                                    // eslint-disable-next-line object-shorthand
                                    return { id: /** @type {any} */ (id) };
                                }),
                        };
                        write('nextSteps_data', data);
                    }
                    return Promise.resolve(data);
                }
                case 'rmf_getData': {
                    /** @type {import('../types/new-tab.ts').RMFData} */
                    let message = { content: undefined };
                    const rmfParam = url.searchParams.get('rmf');

                    // if the message should be delayed, initially return nothing here
                    const delayed = url.searchParams.has('rmf-delay');
                    if (delayed) return Promise.resolve(message);

                    if (rmfParam && rmfParam in rmfDataExamples) {
                        message = rmfDataExamples[rmfParam];
                    }

                    return Promise.resolve(message);
                }
                case 'freemiumPIRBanner_getData': {
                    /** @type {import('../types/new-tab.ts').FreemiumPIRBannerData} */
                    let freemiumPIRBannerMessage = { content: null };
                    const freemiumPIRBannerParam = url.searchParams.get('pir');

                    if (freemiumPIRBannerParam && freemiumPIRBannerParam in freemiumPIRDataExamples) {
                        freemiumPIRBannerMessage = freemiumPIRDataExamples[freemiumPIRBannerParam];
                    }

                    return Promise.resolve(freemiumPIRBannerMessage);
                }
                case 'favorites_getData': {
                    const param = url.searchParams.get('favorites');
                    let data;
                    if (param && param in favorites) {
                        data = favorites[param];
                    } else {
                        data = param ? gen(Number(url.searchParams.get('favorites'))) : read('favorites_data') || favorites.many;
                    }

                    write('favorites_data', data);
                    // return new Promise((resolve) => setTimeout(() => resolve(dataToWrite), 1000))
                    return Promise.resolve(data);
                }
                case 'favorites_getConfig': {
                    /** @type {FavoritesConfig} */
                    const defaultConfig = { expansion: 'collapsed', animation: { kind: 'view-transitions' } };
                    const fromStorage = read('favorites_config') || defaultConfig;
                    if (url.searchParams.get('favorites.config.expansion') === 'expanded') {
                        defaultConfig.expansion = 'expanded';
                    }
                    return Promise.resolve(fromStorage);
                }
                case 'initialSetup': {
                    /** @type {import('../types/new-tab.ts').Widgets} */
                    const widgetsFromStorage = read('widgets') || [
                        { id: 'updateNotification' },
                        { id: 'rmf' },
                        { id: 'freemiumPIRBanner' },
                        { id: 'nextSteps' },
                        { id: 'favorites' },
                    ];

                    /** @type {import('../types/new-tab.ts').WidgetConfigs} */
                    const widgetConfigFromStorage = read('widget_config') || [{ id: 'favorites', visibility: 'visible' }];

                    /** @type {UpdateNotificationData} */
                    let updateNotification = { content: null };
                    const isDelayed = url.searchParams.has('update-notification-delay');

                    if (!isDelayed && url.searchParams.has('update-notification')) {
                        const value = url.searchParams.get('update-notification');
                        if (value && value in updateNotificationExamples) {
                            updateNotification = updateNotificationExamples[value];
                        }
                    }

                    /** @type {import('../types/new-tab.ts').InitialSetupResponse} */
                    const initial = {
                        widgets: widgetsFromStorage,
                        widgetConfigs: widgetConfigFromStorage,
                        platform: { name: 'integration' },
                        env: 'development',
                        locale: 'en',
                        updateNotification,
                    };

                    widgetsFromStorage.push({ id: 'protections' });
                    widgetConfigFromStorage.push({ id: 'protections', visibility: 'visible' });

                    if (url.searchParams.has('omnibar')) {
                        const favoritesWidgetIndex = widgetsFromStorage.findIndex((widget) => widget.id === 'favorites') ?? 0;
                        widgetsFromStorage.splice(favoritesWidgetIndex, 0, { id: 'omnibar' });
                        const favoritesWidgetConfigIndex = widgetConfigFromStorage.findIndex((widget) => widget.id === 'favorites') ?? 0;
                        widgetConfigFromStorage.splice(favoritesWidgetConfigIndex, 0, { id: 'omnibar', visibility: 'visible' });
                    }

                    initial.customizer = customizerData();

                    /** @type {import('../types/new-tab').NewTabPageSettings} */
                    const settings = {
                        customizerDrawer: { state: 'enabled' },
                    };

                    if (url.searchParams.get('autoOpen') === 'true' && settings.customizerDrawer) {
                        settings.customizerDrawer.autoOpen = true;
                    }

                    if (url.searchParams.get('adBlocking') === 'enabled') {
                        settings.adBlocking = { state: 'enabled' };
                    }

                    // feature flags
                    initial.settings = settings;

                    return Promise.resolve(initial);
                }
                default: {
                    return Promise.reject(new Error('unhandled request' + msg));
                }
            }
        },
    });
}

/**
 * @template {{id: string}} T
 * @param {T[]} array
 * @param {string} id
 * @param {number} toIndex
 * @return {T[]}
 */
function reorderArray(array, id, toIndex) {
    const fromIndex = array.findIndex((item) => item.id === id);
    const element = array.splice(fromIndex, 1)[0]; // Remove the element from the original position
    array.splice(toIndex, 0, element); // Insert the element at the new position
    return array;
}
