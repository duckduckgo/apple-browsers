/**
 * @type {import("../../types/new-tab.js").Widgets}
 */
const widgets = [{ id: 'weatherWidget' }, { id: 'newsWidget' }];

/**
 * @type {import("../../types/new-tab.js").WidgetListItem}
 */
const widget = { id: 'newsWidget' };

/**
 * @type {import("../../types/new-tab.js").WidgetConfigs}
 */
const widgetConfigs = [
    { id: 'weatherWidget', visibility: 'visible' },
    { id: 'newsWidget', visibility: 'visible' },
];

/**
 * @type {import("../../types/new-tab.js").WidgetConfigItem}
 */
const widgetConfig = {
    id: 'weatherWidget',
    visibility: 'visible',
};

// #region initialSetupResponse
/**
 * Example of the `InitialSetupResponse`
 *
 * @type {import("../../types/new-tab.js").InitialSetupResponse}
 */
// prettier-ignore
const initialSetupResponse = {
    widgets: [
        { id: 'updateNotification' },
        { id: 'rmf' },
        { id: 'favorites' },
        { id: 'privacyStats' }
    ],
    widgetConfigs: [
        { id: 'rmf', visibility: 'visible' },
        { id: 'nextSteps', visibility: 'visible' },
        { id: 'favorites', visibility: 'visible' },
        { id: 'privacyStats', visibility: 'visible' },
    ],
    env: 'production',
    locale: 'en',
    platform: { name: 'windows' },
    updateNotification: { content: null },
    customizer: {
        theme: 'system',
        userImages: [],
        userColor: null,
        background: { kind: 'default' },
        defaultStyles: {
            lightBackgroundColor: '#E9EBEC',
            darkBackgroundColor: '#27282A',
        },
    },
};

// #endregion initialSetupResponse

export {};
