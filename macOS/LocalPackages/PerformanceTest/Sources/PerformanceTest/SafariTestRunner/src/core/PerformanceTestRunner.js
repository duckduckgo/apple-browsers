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
     * Check if data is consistent using IQR/median threshold
     * @private
     */
    _isDataConsistent(values) {
        if (values.length < 4) return false;

        const sorted = [...values].sort((a, b) => a - b);
        const count = sorted.length;

        // Calculate median
        const mid = Math.floor(count / 2);
        const median = count % 2 === 0
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid];

        if (median <= 0) return false;

        // Calculate IQR (Q3 - Q1) using linear interpolation (matches Swift implementation)
        const q1Index = (count - 1) * 0.25;
        const q1LowerIndex = Math.floor(q1Index);
        const q1UpperIndex = Math.ceil(q1Index);
        const q1 = q1LowerIndex === q1UpperIndex
            ? sorted[q1LowerIndex]
            : sorted[q1LowerIndex] + (q1Index - q1LowerIndex) * (sorted[q1UpperIndex] - sorted[q1LowerIndex]);

        const q3Index = (count - 1) * 0.75;
        const q3LowerIndex = Math.floor(q3Index);
        const q3UpperIndex = Math.ceil(q3Index);
        const q3 = q3LowerIndex === q3UpperIndex
            ? sorted[q3LowerIndex]
            : sorted[q3LowerIndex] + (q3Index - q3LowerIndex) * (sorted[q3UpperIndex] - sorted[q3LowerIndex]);

        const iqr = q3 - q1;
        const coefficientOfVariation = (iqr / median) * 100;

        // Calculate P95/P50 ratio for additional reliability check
        const p50Index = Math.floor((count - 1) * 0.50);
        const p95Index = Math.floor((count - 1) * 0.95);
        const p50 = sorted[p50Index];
        const p95 = sorted[p95Index];
        const ratio = p50 > 0 ? p95 / p50 : 999;

        // Only stop early if we achieve "Good" or better consistency
        // Good: coeffVariation < 20% AND ratio < 2.0x
        // Excellent: coeffVariation < 10% AND ratio < 1.5x
        return coefficientOfVariation < 20.0 && ratio < 2.0;
    }

    /**
     * Run test iterations with session restarts for clean cache
     * Adaptive iterations: starts with minimum, continues until consistent or hits maximum
     * @private
     */
    async _runIterations() {
        const { iterations: minIterations, maxIterations, url } = this.config;

        // Run warm-up iteration (not counted in results)
        this.logger.info('Running warm-up iteration (validates test setup)');
        const warmupResult = await this.services.testExecutor.execute(url, false);

        if (warmupResult.success) {
            this.logger.info(`  ✓ Warm-up completed successfully (${warmupResult.duration}ms)`);
        } else {
            this.logger.warn(`  ⚠ Warm-up failed: ${warmupResult.error}`);
        }

        // Delay after warm-up
        if (!this.isShuttingDown) {
            await this.services.webDriver.sleep(this.config.retryDelay);
        }

        // Run actual test iterations with adaptive logic
        let currentIteration = 0;
        while (currentIteration < maxIterations && !this.isShuttingDown) {
            currentIteration++;
            this.logger.info(`==> Starting iteration ${currentIteration} (min: ${minIterations}, max: ${maxIterations})`);

            try {
                const needsRestart = true;
                const result = await this.services.testExecutor.execute(url, needsRestart);
                this.services.resultsManager.addIterationResult(result, currentIteration);
            } catch (error) {
                this.logger.error(`Iteration ${currentIteration} failed with exception: ${error.message}`, error);
                // Add failed result and continue to next iteration
                this.services.resultsManager.addIterationResult({
                    success: false,
                    url: url,
                    timestamp: new Date().toISOString(),
                    error: error.message,
                    metrics: null
                }, currentIteration);
            }

            // Did we reach minimum iteration number?
            if (currentIteration >= minIterations) {
                try {
                    // Get successful samples
                    const loadCompleteTimes = this.services.resultsManager.results.iterations
                        .filter(iter => iter.success && iter.metrics)
                        .map(iter => iter.metrics.loadComplete || 0)
                        .filter(val => val > 0);

                    // Calculate consistency metrics for display
                    if (loadCompleteTimes.length >= 4) {
                        const sorted = [...loadCompleteTimes].sort((a, b) => a - b);
                        const count = sorted.length;
                        const median = count % 2 === 0 ? (sorted[count/2 - 1] + sorted[count/2]) / 2 : sorted[count/2];
                        const q1Index = (count - 1) * 0.25;
                        const q3Index = (count - 1) * 0.75;
                        const q1 = sorted[Math.floor(q1Index)];
                        const q3 = sorted[Math.floor(q3Index)];
                        const iqr = q3 - q1;
                        const coeffVar = median > 0 ? (iqr / median * 100) : 999;
                        const p50Index = Math.floor((count - 1) * 0.50);
                        const p95Index = Math.floor((count - 1) * 0.95);
                        const p50 = sorted[p50Index];
                        const p95 = sorted[p95Index];
                        const ratio = p50 > 0 ? p95 / p50 : 999;

                        this.logger.info(`Consistency metrics: CoeffVar=${coeffVar.toFixed(1)}%, Ratio=${ratio.toFixed(2)}x (target: <20% AND <2.0x)`);
                        this.logger.info(`  Median=${median.toFixed(0)}ms, IQR=${iqr.toFixed(0)}ms, P50=${p50.toFixed(0)}ms, P95=${p95.toFixed(0)}ms`);

                        const isConsistent = this._isDataConsistent(loadCompleteTimes);
                        this.logger.info(`  Consistency check result: ${isConsistent} (needs BOTH coeffVar<20% AND ratio<2.0x)`);

                        // Did we reach desired consistency?
                        if (isConsistent) {
                            // Yes - STOP
                            this.logger.info(`✓ Achieved 'Good' consistency after ${currentIteration} iterations. Stopping.`);
                            break;
                        }
                        // Otherwise test one more time (continue loop)
                        this.logger.info(`Consistency not yet achieved. Testing iteration ${currentIteration + 1}...`);
                    } else {
                        this.logger.info(`Only ${loadCompleteTimes.length} samples - need 4+ for consistency check. Continuing...`);
                    }
                } catch (error) {
                    this.logger.error(`Consistency check failed: ${error.message}`, error);
                    // Continue testing anyway - better to get more data than stop early
                    this.logger.info(`Continuing to iteration ${currentIteration + 1} despite consistency check error...`);
                }
            }

            // Delay between iterations (except last one)
            if (currentIteration < maxIterations && !this.isShuttingDown) {
                try {
                    await this.services.webDriver.sleep(this.config.retryDelay);
                } catch (error) {
                    this.logger.warn(`Sleep between iterations failed: ${error.message}`);
                    // Continue anyway - the next iteration will reinitialize the driver
                }
            }
        }

        this.logger.info(`==> Loop completed. Final iteration count: ${currentIteration}`);
        this.logger.info(`  Shutdown requested: ${this.isShuttingDown}`);
        this.logger.info(`  Reached max iterations: ${currentIteration >= maxIterations}`);
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