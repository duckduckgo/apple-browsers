import ContentFeature from '../content-feature';

// Set Global Privacy Control property on DOM
export default class GlobalPrivacyControl extends ContentFeature {
    init(args) {
        try {
            // If GPC on, set DOM property prototype to true if not already true
            if (args.globalPrivacyControlValue) {
                // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                if (navigator.globalPrivacyControl) return;
                this.defineProperty(Navigator.prototype, 'globalPrivacyControl', {
                    get: () => true,
                    configurable: true,
                    enumerable: true,
                });
            } else {
                // If GPC off & unsupported by browser, set DOM property prototype to false
                // this may be overwritten by the user agent or other extensions
                // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                if (typeof navigator.globalPrivacyControl !== 'undefined') return;
                this.defineProperty(Navigator.prototype, 'globalPrivacyControl', {
                    get: () => false,
                    configurable: true,
                    enumerable: true,
                });
            }
        } catch {
            // Ignore exceptions that could be caused by conflicting with other extensions
        }
    }
}
