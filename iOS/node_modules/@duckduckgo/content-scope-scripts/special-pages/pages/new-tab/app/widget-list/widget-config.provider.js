import { createContext, h } from 'preact';
import { useContext } from 'preact/hooks';
import { effect, signal, useComputed, useSignal } from '@preact/signals';

/**
 * @typedef {import('../../types/new-tab.js').WidgetConfigs} WidgetConfigs
 * @typedef {import('../../types/new-tab.js').Widgets} Widgets
 * @typedef {import("../../types/new-tab.js").WidgetConfigItem} WidgetConfigItem
 * @typedef {import("./widget-config.service.js").WidgetConfigService} WidgetConfigAPI
 */

export const WidgetConfigContext = createContext({
    /** @type {Widgets} */
    widgets: [],

    /** @type {Record<string, {factory: () => import("preact").ComponentChild}>} */
    entryPoints: {},

    /**
     * A snapshot of the widget config as received at page load. Use this when you
     * don't need up-to-date values.
     * @type {WidgetConfigItem[]}
     */
    widgetConfigItems: [],
    /**
     * The live version of the data in 'widgetConfigItems' above. This represents the very
     * latest updates and can be subscribed to for reactive updates
     * @type {import("@preact/signals").Signal<WidgetConfigItem[]>}
     */
    currentValues: signal([]),

    /** @type {(id:string) => void} */

    toggle: (_id) => {},
});

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 * @param {WidgetConfigItem[]} props.widgetConfigs - the initial config data
 * @param {Record<string, {factory: () => import("preact").ComponentChild}>} props.entryPoints
 * @param {Widgets} props.widgets - the initial widget list
 * @param {WidgetConfigAPI} props.api - the stateful API manager
 */
export function WidgetConfigProvider(props) {
    const currentValues = useSignal(props.widgetConfigs);

    effect(() => {
        const unsub = props.api.onData((widgetConfig) => {
            currentValues.value = widgetConfig.data;
        });
        return () => unsub();
    });

    /**
     * @param {string} id
     */
    function toggle(id) {
        props.api.toggleVisibility(id);
    }

    return (
        <WidgetConfigContext.Provider
            value={{
                // this field is static for the lifespan of the page
                widgets: props.widgets,
                entryPoints: props.entryPoints,
                widgetConfigItems: props.widgetConfigs,
                currentValues,
                toggle,
            }}
        >
            {props.children}
        </WidgetConfigContext.Provider>
    );
}

const WidgetVisibilityContext = createContext({
    id: /** @type {WidgetConfigItem['id']} */ (''),
    /** @type {(id: string) => void} */

    toggle: (_id) => {},
    /** @type {number} */
    index: -1,
    visibility: signal(/** @type {WidgetConfigItem['visibility']} */ ('visible')),
});

export function useVisibility() {
    return useContext(WidgetVisibilityContext);
}

/**
 * This wraps each widget and gives
 * @param {object} props
 * @param {WidgetConfigItem['id']} props.id - the current id key used for storage
 * @param {number} props.index - the current id key used for storage
 * @param {import("preact").ComponentChild} props.children
 */
export function WidgetVisibilityProvider(props) {
    const { toggle, currentValues } = useContext(WidgetConfigContext);
    const visibility = useComputed(() => {
        const matchingConfig = currentValues.value.find((x) => x.id === props.id);
        if (!matchingConfig) throw new Error('unreachable. Must find widget config via id: ' + props.id);
        return matchingConfig.visibility;
    });

    return (
        <WidgetVisibilityContext.Provider
            value={{
                visibility,
                id: props.id,
                toggle,
                index: props.index,
            }}
        >
            {props.children}
        </WidgetVisibilityContext.Provider>
    );
}
