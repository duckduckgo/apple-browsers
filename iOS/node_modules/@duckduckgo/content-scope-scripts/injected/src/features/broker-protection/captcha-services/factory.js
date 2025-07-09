/**
 * Factory for captcha providers
 */
export class CaptchaFactory {
    constructor() {
        this.providers = new Map();
    }

    /**
     * Register a captcha provider
     * @param {import('./providers/provider.interface').CaptchaProvider} provider - The provider to register
     */
    registerProvider(provider) {
        this.providers.set(provider.getType(), provider);
    }

    /**
     * Get a provider by type
     * @param {string} type - The provider type
     * @returns {import('./providers/provider.interface').CaptchaProvider|null}
     */
    getProviderByType(type) {
        return this.providers.get(type) || null;
    }

    /**
     * Detect the captcha provider based on the element
     * @param {Document | HTMLElement} root
     * @param {HTMLElement} element - The element to check
     * @returns {import('./providers/provider.interface').CaptchaProvider|null}
     */
    detectProvider(root, element) {
        return this._getAllProviders().find((provider) => provider.isSupportedForElement(root, element)) || null;
    }

    /**
     * Detect the captcha provider based on the root document
     * @param {HTMLElement} element - The element to check
     * @returns {import('./providers/provider.interface').CaptchaProvider|null}
     */
    detectSolveProvider(element) {
        return this._getAllProviders().find((provider) => provider.canSolve(element)) || null;
    }

    /**
     * Get all registered providers
     * @private
     * @returns {Array<import('./providers/provider.interface').CaptchaProvider>}
     */
    _getAllProviders() {
        return Array.from(this.providers.values());
    }
}
