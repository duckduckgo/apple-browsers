import { createContext, h } from 'preact';
import { useCallback } from 'preact/hooks';
import { signal, useSignal, useSignalEffect } from '@preact/signals';
import { useThemes } from './themes.js';
import { applyDefaultStyles } from './utils.js';

/**
 * @typedef {import('../../types/new-tab.js').CustomizerData} CustomizerData
 * @typedef {import('../../types/new-tab.js').BackgroundData} BackgroundData
 * @typedef {import('../../types/new-tab.js').ThemeData} ThemeData
 * @typedef {import('../../types/new-tab.js').UserImageData} UserImageData
 * @typedef {import('../../types/new-tab.js').UserImageContextMenu} UserImageContextMenu
 * @typedef {import('../service.hooks.js').State<CustomizerData, undefined>} State
 * @typedef {import('../service.hooks.js').Events<CustomizerData, undefined>} Events
 */

/**
 * These are the values exposed to consumers.
 */
export const CustomizerThemesContext = createContext({
    /** @type {import("@preact/signals").Signal<'light' | 'dark'>} */
    main: signal('light'),
    /** @type {import("@preact/signals").Signal<'light' | 'dark'>} */
    browser: signal('light'),
});

export const CustomizerContext = createContext({
    /** @type {import("@preact/signals").Signal<CustomizerData>} */
    data: signal({
        background: { kind: 'default' },
        userImages: [],
        userColor: null,
        theme: 'system',
    }),
    /** @type {(bg: BackgroundData) => void} */
    select: (_) => {},
    upload: () => {},
    /**
     * @type {(theme: ThemeData) => void}
     */
    setTheme: (_) => {},
    /**
     * @type {(id: string) => void}
     */
    deleteImage: (_) => {},
    /**
     * @param {UserImageContextMenu} _params
     */
    customizerContextMenu: (_params) => {},
});

/**
 * A data provider that will use `RMFService` to fetch data, subscribe
 * to updates and modify state.
 *
 * @param {Object} props
 * @param {import("./customizer.service.js").CustomizerService} props.service
 * @param {CustomizerData} props.initialData
 * @param {import("preact").ComponentChild} props.children
 */
export function CustomizerProvider({ service, initialData, children }) {
    // const [state, dispatch] = useReducer(withLog('RMFProvider', reducer), initial)
    const data = useSignal(initialData);
    const { main, browser } = useThemes(data);

    useSignalEffect(() => {
        const unsub = service.onBackground((evt) => {
            data.value = { ...data.value, background: evt.data.background };
        });
        const unsub1 = service.onTheme((evt) => {
            data.value = { ...data.value, theme: evt.data.theme };
        });
        const unsub2 = service.onImages((evt) => {
            data.value = { ...data.value, userImages: evt.data.userImages };
        });
        const unsub3 = service.onColor((evt) => {
            data.value = { ...data.value, userColor: evt.data.userColor };
        });

        return () => {
            unsub();
            unsub1();
            unsub2();
            unsub3();
        };
    });

    useSignalEffect(() => {
        const unsub = service.onTheme((evt) => {
            if (evt.source === 'subscription') {
                applyDefaultStyles(evt.data.defaultStyles);
            }
        });

        return () => {
            unsub();
        };
    });

    /** @type {(bg: BackgroundData) => void} */
    const select = useCallback(
        (bg) => {
            service.setBackground(bg);
        },
        [service],
    );

    const upload = useCallback(() => {
        service.upload();
    }, [service]);

    const setTheme = useCallback(
        (theme) => {
            service.setTheme(theme);
        },
        [service],
    );

    const deleteImage = useCallback(
        (id) => {
            service.deleteImage(id);
        },
        [service],
    );

    /** @type {(p: UserImageContextMenu) => void} */
    const customizerContextMenu = useCallback((params) => service.contextMenu(params), [service]);

    return (
        <CustomizerContext.Provider value={{ data, select, upload, setTheme, deleteImage, customizerContextMenu }}>
            <CustomizerThemesContext.Provider value={{ main, browser }}>{children}</CustomizerThemesContext.Provider>
        </CustomizerContext.Provider>
    );
}
