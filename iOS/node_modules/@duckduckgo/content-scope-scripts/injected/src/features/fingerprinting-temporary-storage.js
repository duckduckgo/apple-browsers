import ContentFeature from '../content-feature';

export default class FingerprintingTemporaryStorage extends ContentFeature {
    init() {
        const navigator = globalThis.navigator;
        const Navigator = globalThis.Navigator;

        /**
         * Temporary storage can be used to determine hard disk usage and size.
         * This will limit the max storage to 4GB without completely disabling the
         * feature.
         */
        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
        if (navigator.webkitTemporaryStorage) {
            try {
                // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                const org = navigator.webkitTemporaryStorage.queryUsageAndQuota;
                // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                const tStorage = navigator.webkitTemporaryStorage;
                tStorage.queryUsageAndQuota = function queryUsageAndQuota(callback, err) {
                    const modifiedCallback = function (usedBytes, grantedBytes) {
                        const maxBytesGranted = 4 * 1024 * 1024 * 1024;
                        const spoofedGrantedBytes = Math.min(grantedBytes, maxBytesGranted);
                        callback(usedBytes, spoofedGrantedBytes);
                    };
                    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                    org.call(navigator.webkitTemporaryStorage, modifiedCallback, err);
                };
                this.defineProperty(Navigator.prototype, 'webkitTemporaryStorage', {
                    get: () => tStorage,
                    enumerable: true,
                    configurable: true,
                });
            } catch (e) {}
        }
    }
}
