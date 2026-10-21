/**
 * WebDriver service for managing browser automation
 *
 * @module services/WebDriverService
 */

const { By, until } = require('selenium-webdriver');
const { Builder } = require('selenium-webdriver');
const safari = require('selenium-webdriver/safari');

/**
 * Service for managing Safari WebDriver instances
 */
class WebDriverService {
    constructor(logger) {
        this.logger = logger;
        this.driver = null;
        this.isInitialized = false;
    }

    /**
     * Initialize Safari WebDriver
     * @returns {Promise<WebDriver>} WebDriver instance
     */
    async initialize() {
        if (this.isInitialized && this.driver) {
            this.logger.debug('WebDriver already initialized');
            return this.driver;
        }

        try {
            this.logger.debug('Initializing Safari WebDriver');

            const options = new safari.Options();

            // Try to disable automation banner (may not work in all Safari versions)
            options.set('safari:automaticInspection', false);
            options.set('safari:automaticProfiling', false);

            this.driver = await new Builder()
                .forBrowser('safari')
                .setSafariOptions(options)
                .build();

            // Set window size to match testing environment
            await this.driver.manage().window().setRect({
                width: 1024,
                height: 870,
                x: 0,
                y: 0
            });

            this.isInitialized = true;
            this.logger.debug('Safari WebDriver initialized successfully (window: 1024x870)');

            // Get browser capabilities
            const capabilities = await this.getCapabilities();
            this.logger.debug('Browser capabilities', capabilities);

            return this.driver;
        } catch (error) {
            this.logger.error('Failed to initialize Safari WebDriver', error);

            // Provide helpful error message with automation setup instructions
            throw new Error(
                `Safari WebDriver initialization failed: ${error.message}\n\n` +
                'If Safari is not connecting, ensure Remote Automation is enabled:\n' +
                '1. Open Safari → Settings → Advanced\n' +
                '2. Enable "Show Develop menu in menu bar"\n' +
                '3. In the Develop menu, select "Allow Remote Automation"'
            );
        }
    }

    /**
     * Get browser capabilities
     * @returns {Promise<Object>} Browser capabilities
     */
    async getCapabilities() {
        if (!this.isInitialized) {
            throw new Error('WebDriver not initialized');
        }

        try {
            const caps = await this.driver.getCapabilities();
            return {
                browserName: caps.get('browserName'),
                browserVersion: caps.get('browserVersion') || 'unknown',
                platformName: caps.get('platformName')
            };
        } catch (error) {
            this.logger.warn('Could not retrieve capabilities', error);
            return {
                browserName: 'safari',
                browserVersion: 'unknown',
                platformName: 'unknown'
            };
        }
    }

    /**
     * Navigate to URL
     * @param {string} url - URL to navigate to
     */
    async navigateTo(url) {
        if (!this.isInitialized) {
            throw new Error('WebDriver not initialized');
        }

        this.logger.debug(`Navigating to: ${url}`);
        await this.driver.get(url);
    }

    /**
     * Wait for element to be located
     * @param {string} selector - CSS selector
     * @param {number} timeout - Timeout in milliseconds
     */
    async waitForElement(selector, timeout = 30000) {
        if (!this.isInitialized) {
            throw new Error('WebDriver not initialized');
        }

        await this.driver.wait(until.elementLocated(By.css(selector)), timeout);
    }

    /**
     * Execute JavaScript in browser context
     * @param {string} script - JavaScript to execute
     * @returns {Promise<any>} Script execution result
     */
    async executeScript(script) {
        if (!this.isInitialized) {
            throw new Error('WebDriver not initialized');
        }

        return await this.driver.executeScript(script);
    }

    /**
     * Wait for condition
     * @param {Function} condition - Condition function
     * @param {number} timeout - Timeout in milliseconds
     */
    async waitForCondition(condition, timeout = 30000) {
        if (!this.isInitialized) {
            throw new Error('WebDriver not initialized');
        }

        await this.driver.wait(condition, timeout);
    }

    /**
     * Sleep for specified duration
     * @param {number} ms - Duration in milliseconds
     */
    async sleep(ms) {
        if (!this.isInitialized) {
            throw new Error('WebDriver not initialized');
        }

        await this.driver.sleep(ms);
    }

    /**
     * Close the WebDriver instance
     */
    async quit() {
        if (!this.driver) {
            return;
        }

        try {
            this.logger.debug('Closing Safari WebDriver');
            await this.driver.quit();
            this.driver = null;
            this.isInitialized = false;
            this.logger.debug('WebDriver closed successfully');
        } catch (error) {
            this.logger.warn('Error during WebDriver cleanup', error);
            // Reset state even if error occurred
            this.driver = null;
            this.isInitialized = false;
        }
    }

    /**
     * Check if WebDriver is initialized
     * @returns {boolean} Initialization status
     */
    isReady() {
        return this.isInitialized && this.driver !== null;
    }
}

module.exports = WebDriverService;