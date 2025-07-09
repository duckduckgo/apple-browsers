/**
 * @typedef {import("../../types/new-tab.js").CustomizerData} CustomizerData
 * @typedef {import("../../types/new-tab.js").UserImageData} UserImageData
 * @typedef {import("../../types/new-tab.js").UserColorData} UserColorData
 * @typedef {import("../../types/new-tab.js").UserImageContextMenu} UserImageContextMenu
 * @typedef {import("../../types/new-tab.js").ThemeData} ThemeData
 * @typedef {import("../../types/new-tab.js").BackgroundData} BackgroundData
 */
import { Service } from '../service.js';

/**
 * @document ./customizer.md
 */

export class CustomizerService {
    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed, expected to have a `subscribe` method.
     * @param {CustomizerData} initial
     * @internal
     */
    constructor(ntp, initial) {
        this.ntp = ntp;
        /** @type {Service<BackgroundData>} */
        this.bgService = new Service(
            {
                subscribe: (cb) => ntp.messaging.subscribe('customizer_onBackgroundUpdate', cb),
                persist: (data) => {
                    ntp.messaging.notify('customizer_setBackground', data);
                },
            },
            { background: initial.background },
        );
        /** @type {Service<ThemeData>} */
        this.themeService = new Service(
            {
                subscribe: (cb) => ntp.messaging.subscribe('customizer_onThemeUpdate', cb),
            },
            { theme: initial.theme },
        );
        /** @type {Service<UserImageData>} */
        this.imagesService = new Service(
            {
                subscribe: (cb) => ntp.messaging.subscribe('customizer_onImagesUpdate', cb),
            },
            { userImages: initial.userImages },
        );
        /** @type {Service<UserColorData>} */
        this.colorService = new Service(
            {
                subscribe: (cb) => ntp.messaging.subscribe('customizer_onColorUpdate', cb),
            },
            { userColor: initial.userColor },
        );
    }

    /**
     * @internal
     */
    destroy() {
        this.bgService.destroy();
        this.themeService.destroy();
        this.imagesService.destroy();
        this.colorService.destroy();
    }

    /**
     * @param {(evt: {data: BackgroundData, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onBackground(cb) {
        return this.bgService.onData(cb);
    }
    /**
     * @param {(evt: {data: ThemeData, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onTheme(cb) {
        return this.themeService.onData(cb);
    }
    /**
     * @param {(evt: {data: UserImageData, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onImages(cb) {
        return this.imagesService.onData(cb);
    }
    /**
     * @param {(evt: {data: UserColorData, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onColor(cb) {
        return this.colorService.onData(cb);
    }

    /**
     * @param {BackgroundData} bg
     */
    setBackground(bg) {
        this.bgService.update((_) => {
            return bg;
        });
        if (bg.background.kind === 'hex') {
            this.colorService.update((_old) => {
                if (bg.background.kind !== 'hex') throw new Error('unreachable code path');
                return { userColor: structuredClone(bg.background) };
            });
        }
    }

    /**
     * @param {string} id
     */
    deleteImage(id) {
        this.imagesService.update((data) => {
            return {
                ...data,
                userImages: data.userImages.filter((img) => img.id !== id),
            };
        });
        this.ntp.messaging.notify('customizer_deleteImage', { id });
    }

    /**
     *
     */
    upload() {
        this.ntp.messaging.notify('customizer_upload');
    }

    /**
     * @param {ThemeData} theme
     */
    setTheme(theme) {
        this.themeService.update((_data) => {
            return theme;
        });
        this.ntp.messaging.notify('customizer_setTheme', theme);
    }

    /**
     * @param {import('../../types/new-tab.js').UserImageContextMenu} params
     */
    contextMenu(params) {
        this.ntp.messaging.notify('customizer_contextMenu', params);
    }
}
