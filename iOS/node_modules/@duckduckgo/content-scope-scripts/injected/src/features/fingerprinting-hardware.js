import ContentFeature from '../content-feature';

export default class FingerprintingHardware extends ContentFeature {
    init() {
        this.wrapProperty(globalThis.Navigator.prototype, 'keyboard', {
            get: () => {
                // @ts-expect-error - error TS2554: Expected 2 arguments, but got 1.
                return this.getFeatureAttr('keyboard');
            },
        });

        this.wrapProperty(globalThis.Navigator.prototype, 'hardwareConcurrency', {
            get: () => {
                return this.getFeatureAttr('hardwareConcurrency', 2);
            },
        });

        this.wrapProperty(globalThis.Navigator.prototype, 'deviceMemory', {
            get: () => {
                return this.getFeatureAttr('deviceMemory', 8);
            },
        });
    }
}
