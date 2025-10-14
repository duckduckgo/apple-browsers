/**
 * Main performance test orchestrator
 *
 * @module core/PerformanceTestRunner
 */

const Logger = require('../utils/Logger');
const WebDriverService = require('../services/WebDriverService');
const MetricsCollector = require('../services/MetricsCollector');
const ResultsManager = require('../services/ResultsManager');
const TestExecutor = require('./TestExecutor');

/**
 * Main orchestrator for performance test execution
 */
class PerformanceTestRunner {
    constructor(configuration) {
        this.config = configuration;
        this.logger = new Logger({
            verbose: configuration.verbose
        });

        this.isShuttingDown = false;
        this.services = {};

        this._setupShutdownHandlers();
    }

    /**
     * Setup graceful shutdown handlers
     * @private
     */
    _setupShutdownHandlers() {
        const handleShutdown = async (signal) => {
            if (this.isShuttingDown) return;
            this.isShuttingDown = true;

            this.logger.info(`Received ${signal}, initiating graceful shutdown`);

            // Mark results as interrupted
            if (this.services.resultsManager) {
                this.services.resultsManager.markInterrupted();
            }

            await this.cleanup();
            process.exit(0);
        };

        process.on('SIGINT', () => handleShutdown('SIGINT'));
        process.on('SIGTERM', () => handleShutdown('SIGTERM'));

        // Handle uncaught errors
        process.on('uncaughtException', (error) => {
            this.logger.error('Uncaught exception', error);
            handleShutdown('uncaughtException');
        });

        process.on('unhandledRejection', (reason, promise) => {
            this.logger.error('Unhandled promise rejection', { reason, promise });
            handleShutdown('unhandledRejection');
        });
    }

    /**
     * Initialize all services
     * @private
     */
    async _initializeServices() {
        this.logger.info('Initializing services');

        // Initialize services
        this.services.webDriver = new WebDriverService(this.logger.child('WebDriver'));
        this.services.metricsCollector = new MetricsCollector(this.logger.child('Metrics'));
        this.services.resultsManager = new ResultsManager(this.config, this.logger.child('Results'));

        // Load metrics script
        await this.services.metricsCollector.loadScript();

        // Initialize WebDriver
        await this.services.webDriver.initialize();

        // Get browser capabilities
        const capabilities = await this.services.webDriver.getCapabilities();
        this.services.resultsManager.setBrowserVersion(capabilities.browserVersion);

        // Create test executor
        this.services.testExecutor = new TestExecutor(
            this.services.webDriver,
            this.services.metricsCollector,
            this.config,
            this.logger.child('Executor')
        );

        this.logger.info('Services initialized successfully');
    }

    /**
     * Run the performance test
     * @returns {Promise<Object>} Test results
     */
    async run() {
        try {
            this.logger.info('Starting Safari Performance Test');
            this.logger.info(`Configuration:`, this.config.toObject());

            // Initialize services + iterations
            await this._initializeServices();
            await this._runIterations();

            // Finalize and save results
            await this._finalizeResults();

            return {
                success: true,
                results: this.services.resultsManager.getResults()
            };

        } catch (error) {
            this.logger.error('Test execution failed', error);

            // Try to save partial results
            if (this.services.resultsManager) {
                await this._finalizeResults();
            }

            return {
                success: false,
                error: error.message,
                results: this.services.resultsManager?.getResults()
            };

        } finally {
            await this.cleanup();
        }
    }

    /**
     * Run test iterations with session restarts for clean cache
     * @private
     */
    async _runIterations() {
        const { iterations, url } = this.config;

        // Note: With session restarts, warm-up benefits are limited to:
        // - OS-level DNS caching
        // - Network route optimization
        // - Ensuring test setup works
        // Browser-level warm-up is lost when we restart for each iteration

        // Run warm-up iteration (not counted in results)
        this.logger.info('Running warm-up iteration (validates test setup)');
        const warmupResult = await this.services.testExecutor.execute(url, false); // Keep session for warm-up

        if (warmupResult.success) {
            this.logger.info(`  ✓ Warm-up completed successfully (${warmupResult.duration}ms)`);
        } else {
            this.logger.warn(`  ⚠ Warm-up failed: ${warmupResult.error}`);
        }

        // Delay after warm-up
        if (!this.isShuttingDown) {
            await this.services.webDriver.sleep(this.config.retryDelay);
        }

        // Run actual test iterations
        // Each iteration restarts WebDriver to match Swift's complete cache clearing
        for (let i = 1; i <= iterations && !this.isShuttingDown; i++) {
            this.logger.info(`Running iteration ${i} of ${iterations}`);

            // First iteration after warm-up still needs restart for clean cache
            const needsRestart = true; // Always restart for consistent clean cache

            const result = await this.services.testExecutor.execute(url, needsRestart);
            this.services.resultsManager.addIterationResult(result, i);

            if (result.success) {
                this.logger.info(`  ✓ Completed successfully (${result.duration}ms)`);
            } else {
                this.logger.error(`  ✗ Failed: ${result.error}`);
            }

            // Delay between iterations (except last one)
            if (i < iterations && !this.isShuttingDown) {
                await this.services.webDriver.sleep(this.config.retryDelay);
            }
        }
    }

    /**
     * Finalize and save results
     * @private
     */
    async _finalizeResults() {
        if (!this.services.resultsManager) return;

        this.services.resultsManager.finalize();

        // Save results to file
        await this.services.resultsManager.save();

        // Print summary
        this.services.resultsManager.printSummary();
    }

    /**
     * Cleanup resources
     */
    async cleanup() {
        this.logger.info('Cleaning up resources');

        if (this.services.webDriver) {
            await this.services.webDriver.quit();
        }

        this.logger.info('Cleanup complete');
    }
}

module.exports = PerformanceTestRunner;