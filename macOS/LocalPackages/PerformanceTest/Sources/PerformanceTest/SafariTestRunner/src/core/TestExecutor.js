/**
 * Test executor for running performance tests
 *
 * @module core/TestExecutor
 */

/**
 * Executor for individual performance test iterations
 */
class TestExecutor {
    constructor(webDriverService, metricsCollector, configuration, logger) {
        this.webDriver = webDriverService;
        this.metricsCollector = metricsCollector;
        this.config = configuration;
        this.logger = logger;
    }

    /**
     * Execute a single test iteration
     * @param {string} url - URL to test
     * @param {boolean} restartSession - Whether to restart WebDriver for clean cache
     * @returns {Promise<Object>} Test result
     */
    async execute(url, restartSession = true) {
        const startTime = Date.now();
        const executionLogger = this.logger.child(`iteration`);

        try {
            executionLogger.debug('Starting test execution');

            // Restart WebDriver session for complete cache clearing
            // Each new session gets a fresh ephemeral sandbox with clean cache
            if (restartSession) {
                executionLogger.debug('Restarting WebDriver session for clean cache');

                // Quit current session (destroys ephemeral sandbox)
                await this.webDriver.quit();

                // Delay for cleanup (configurable)
                await new Promise(resolve => setTimeout(resolve, this.config.sessionRestartDelay));

                // Initialize new session (creates fresh sandbox with clean cache)
                await this.webDriver.initialize();

                executionLogger.debug('Fresh WebDriver session started with clean cache');
            }

            // Navigate to URL
            await this._navigateToUrl(url);

            // Wait for page to be ready
            await this._waitForPageReady();

            // Trigger lazy-loaded content
            await this._triggerLazyContent();

            // Collect metrics
            const metrics = await this._collectMetrics();

            const duration = Date.now() - startTime;
            executionLogger.debug(`Test completed in ${duration}ms`);

            return {
                success: true,
                url: url,
                timestamp: new Date().toISOString(),
                duration: duration,
                metrics: metrics
            };

        } catch (error) {
            const duration = Date.now() - startTime;
            executionLogger.error(`Test failed after ${duration}ms`, error);

            return {
                success: false,
                url: url,
                timestamp: new Date().toISOString(),
                duration: duration,
                error: error.message,
                metrics: null
            };
        }
    }

    /**
     * Navigate to URL
     * @private
     */
    async _navigateToUrl(url) {
        this.logger.debug(`Navigating to: ${url}`);
        await this.webDriver.navigateTo(url);
    }

    /**
     * Wait for page to be ready
     * @private
     */
    async _waitForPageReady() {
        this.logger.debug('Waiting for page to be ready');

        // Wait for body element
        await this.webDriver.waitForElement('body', this.config.timeout);

        // Wait for complete state with navigation timing
        await this.webDriver.waitForCondition(async () => {
            try {
                const state = await this.webDriver.executeScript(`
                    return {
                        readyState: document.readyState,
                        hasNav: performance.getEntriesByType('navigation').length > 0,
                        loadEventEnd: performance.getEntriesByType('navigation')[0]?.loadEventEnd || 0
                    };
                `);

                const isReady = state.readyState === 'complete' &&
                               state.hasNav &&
                               state.loadEventEnd > 0;

                if (!isReady) {
                    this.logger.debug('Page not ready yet', state);
                }

                return isReady;
            } catch (error) {
                this.logger.debug('Error checking page state', error);
                return false;
            }
        }, this.config.timeout);

        this.logger.debug('Page is ready');
    }

    /**
     * Trigger lazy-loaded content
     * @private
     */
    async _triggerLazyContent() {
        this.logger.debug('Triggering lazy-loaded content');

        // Initial stability delay
        await this.webDriver.sleep(this.config.stabilityDelay);

        // Scroll to trigger LCP
        await this.webDriver.executeScript('window.scrollTo(0, 300);');
        await this.webDriver.sleep(this.config.scrollDelay);

        // Additional scroll for layout shifts
        await this.webDriver.executeScript('window.scrollTo(0, 600);');
        await this.webDriver.sleep(this.config.scrollDelay);

        this.logger.debug('Lazy content triggered');
    }

    /**
     * Collect performance metrics with retries
     * @private
     */
    async _collectMetrics() {
        const script = this.metricsCollector.prepareScript();

        for (let attempt = 1; attempt <= this.config.maxRetries; attempt++) {
            this.logger.debug(`Collecting metrics (attempt ${attempt}/${this.config.maxRetries})`);

            try {
                const metrics = await this.webDriver.executeScript(script);

                if (this.metricsCollector.validateMetrics(metrics)) {
                    return this.metricsCollector.processMetrics(metrics);
                }

                this.logger.warn(`Invalid metrics on attempt ${attempt}`, metrics);

                if (attempt < this.config.maxRetries) {
                    await this.webDriver.sleep(this.config.retryDelay);
                }

            } catch (error) {
                this.logger.warn(`Script execution error on attempt ${attempt}`, error);

                if (attempt === this.config.maxRetries) {
                    throw error;
                }

                await this.webDriver.sleep(this.config.retryDelay);
            }
        }

        throw new Error(`Failed to collect valid metrics after ${this.config.maxRetries} attempts`);
    }
}

module.exports = TestExecutor;