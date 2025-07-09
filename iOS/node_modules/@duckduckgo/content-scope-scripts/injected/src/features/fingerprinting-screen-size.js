import ContentFeature from '../content-feature';

export default class FingerprintingScreenSize extends ContentFeature {
    origPropertyValues = {};

    init() {
        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
        this.origPropertyValues.availTop = globalThis.screen.availTop;
        this.wrapProperty(globalThis.Screen.prototype, 'availTop', {
            get: () => this.getFeatureAttr('availTop', 0),
        });

        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
        this.origPropertyValues.availLeft = globalThis.screen.availLeft;
        this.wrapProperty(globalThis.Screen.prototype, 'availLeft', {
            get: () => this.getFeatureAttr('availLeft', 0),
        });

        this.origPropertyValues.availWidth = globalThis.screen.availWidth;
        const forcedAvailWidthValue = globalThis.screen.width;
        this.wrapProperty(globalThis.Screen.prototype, 'availWidth', {
            get: () => forcedAvailWidthValue,
        });

        this.origPropertyValues.availHeight = globalThis.screen.availHeight;
        const forcedAvailHeightValue = globalThis.screen.height;
        this.wrapProperty(globalThis.Screen.prototype, 'availHeight', {
            get: () => forcedAvailHeightValue,
        });

        this.origPropertyValues.colorDepth = globalThis.screen.colorDepth;
        this.wrapProperty(globalThis.Screen.prototype, 'colorDepth', {
            get: () => this.getFeatureAttr('colorDepth', 24),
        });

        this.origPropertyValues.pixelDepth = globalThis.screen.pixelDepth;
        this.wrapProperty(globalThis.Screen.prototype, 'pixelDepth', {
            get: () => this.getFeatureAttr('pixelDepth', 24),
        });

        globalThis.window.addEventListener('resize', () => {
            this.setWindowDimensions();
        });
        this.setWindowDimensions();
    }

    /**
     * normalize window dimensions, if more than one monitor is in play.
     *  X/Y values are set in the browser based on distance to the main monitor top or left, which
     * can mean second or more monitors have very large or negative values. This function maps a given
     * given coordinate value to the proper place on the main screen.
     */
    normalizeWindowDimension(value, targetDimension) {
        if (value > targetDimension) {
            return value % targetDimension;
        }
        if (value < 0) {
            return targetDimension + value;
        }
        return value;
    }

    setWindowPropertyValue(property, value) {
        // Here we don't update the prototype getter because the values are updated dynamically
        try {
            this.defineProperty(globalThis, property, {
                get: () => value,

                set: () => {},
                configurable: true,
                enumerable: true,
            });
        } catch (e) {}
    }

    /**
     * Fix window dimensions. The extension runs in a different JS context than the
     * page, so we can inject the correct screen values as the window is resized,
     * ensuring that no information is leaked as the dimensions change, but also that the
     * values change correctly for valid use cases.
     */
    setWindowDimensions() {
        try {
            const window = globalThis;
            const top = globalThis.top;

            const normalizedY = this.normalizeWindowDimension(window.screenY, window.screen.height);
            const normalizedX = this.normalizeWindowDimension(window.screenX, window.screen.width);
            if (normalizedY <= this.origPropertyValues.availTop) {
                this.setWindowPropertyValue('screenY', 0);
                this.setWindowPropertyValue('screenTop', 0);
            } else {
                this.setWindowPropertyValue('screenY', normalizedY);
                this.setWindowPropertyValue('screenTop', normalizedY);
            }

            // @ts-expect-error -  error TS18047: 'top' is possibly 'null'.
            if (top.window.outerHeight >= this.origPropertyValues.availHeight - 1) {
                // @ts-expect-error -  error TS18047: 'top' is possibly 'null'.
                this.setWindowPropertyValue('outerHeight', top.window.screen.height);
            } else {
                try {
                    // @ts-expect-error -  error TS18047: 'top' is possibly 'null'.
                    this.setWindowPropertyValue('outerHeight', top.window.outerHeight);
                } catch (e) {
                    // top not accessible to certain iFrames, so ignore.
                }
            }

            if (normalizedX <= this.origPropertyValues.availLeft) {
                this.setWindowPropertyValue('screenX', 0);
                this.setWindowPropertyValue('screenLeft', 0);
            } else {
                this.setWindowPropertyValue('screenX', normalizedX);
                this.setWindowPropertyValue('screenLeft', normalizedX);
            }

            // @ts-expect-error -  error TS18047: 'top' is possibly 'null'.
            if (top.window.outerWidth >= this.origPropertyValues.availWidth - 1) {
                // @ts-expect-error -  error TS18047: 'top' is possibly 'null'.
                this.setWindowPropertyValue('outerWidth', top.window.screen.width);
            } else {
                try {
                    // @ts-expect-error -  error TS18047: 'top' is possibly 'null'.
                    this.setWindowPropertyValue('outerWidth', top.window.outerWidth);
                } catch (e) {
                    // top not accessible to certain iFrames, so ignore.
                }
            }
        } catch (e) {
            // in a cross domain iFrame, top.window is not accessible.
        }
    }
}
