#!/usr/bin/env node

/**
 * Safari Performance Test Runner
 * Production-ready script for measuring web page performance metrics
 *
 * @copyright 2024 DuckDuckGo
 * @license Apache-2.0
 */

const { Builder, By, until } = require('selenium-webdriver');
const safari = require('selenium-webdriver/safari');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

// Constants
const DEFAULT_ITERATIONS = 1;
const DEFAULT_OUTPUT_FOLDER = '.';
const DEFAULT_TIMEOUT = 30000;
const DEFAULT_RETRY_DELAY = 500;
const DEFAULT_SCROLL_DELAY = 500;
const DEFAULT_STABILITY_DELAY = 500;
const MAX_RETRIES = 3;

// Exit codes
const EXIT_SUCCESS = 0;
const EXIT_INVALID_ARGS = 1;
const EXIT_INVALID_URL = 2;
const EXIT_SCRIPT_NOT_FOUND = 3;
const EXIT_DRIVER_ERROR = 4;
const EXIT_RUNTIME_ERROR = 5;

/**
 * Logger class for consistent logging
 */
class Logger {
    constructor(verbose = false) {
        this.verbose = verbose;
    }

    info(message) {
        console.log(`[INFO] ${message}`);
    }

    error(message) {
        console.error(`[ERROR] ${message}`);
    }

    debug(message) {
        if (this.verbose) {
            console.log(`[DEBUG] ${message}`);
        }
    }

    warn(message) {
        console.warn(`[WARN] ${message}`);
    }
}

/**
 * Configuration class to manage test settings
 */
class TestConfiguration {
    constructor(args) {
        this.parseArguments(args);
        this.validateConfiguration();
    }

    parseArguments(args) {
        // Check for help flag
        if (args.length < 1 || args.includes('--help') || args.includes('-h')) {
            this.showHelp();
            process.exit(EXIT_SUCCESS);
        }

        // Parse required and optional arguments
        this.url = args[0];
        this.iterations = parseInt(args[1]) || DEFAULT_ITERATIONS;
        this.outputFolder = args[2] || DEFAULT_OUTPUT_FOLDER;
        this.verbose = args.includes('--verbose') || args.includes('-v');
        this.timeout = DEFAULT_TIMEOUT;
        this.retryDelay = DEFAULT_RETRY_DELAY;
        this.scrollDelay = DEFAULT_SCROLL_DELAY;
        this.stabilityDelay = DEFAULT_STABILITY_DELAY;

        // Initialize logger with verbose flag
        this.logger = new Logger(this.verbose);
    }

    validateConfiguration() {
        // Validate URL
        try {
            new URL(this.url);
        } catch (error) {
            console.error(`Invalid URL: ${this.url}`);
            console.error(`Error: ${error.message}`);
            process.exit(EXIT_INVALID_URL);
        }

        // Validate iterations
        if (isNaN(this.iterations) || this.iterations < 1 || this.iterations > 1000) {
            console.error(`Invalid iterations: ${this.iterations}. Must be between 1 and 1000.`);
            process.exit(EXIT_INVALID_ARGS);
        }

        // Validate and create output folder
        try {
            if (!fs.existsSync(this.outputFolder)) {
                fs.mkdirSync(this.outputFolder, { recursive: true });
            }
        } catch (error) {
            console.error(`Failed to create output folder: ${this.outputFolder}`);
            console.error(`Error: ${error.message}`);
            process.exit(EXIT_INVALID_ARGS);
        }
    }

    showHelp() {
        console.log('Safari Performance Test Runner');
        console.log('');
        console.log('Usage: node safari-performance-test.js <URL> [iterations] [output-folder] [options]');
        console.log('');
        console.log('Arguments:');
        console.log('  URL           The URL to test (required)');
        console.log('  iterations    Number of test iterations (default: 1, max: 1000)');
        console.log('  output-folder Output folder for results (default: current directory)');
        console.log('');
        console.log('Options:');
        console.log('  --verbose, -v Enable verbose logging');
        console.log('  --help, -h    Show this help message');
        console.log('');
        console.log('Examples:');
        console.log('  node safari-performance-test.js https://example.com');
        console.log('  node safari-performance-test.js https://example.com 5');
        console.log('  node safari-performance-test.js https://example.com 5 ./results');
        console.log('  node safari-performance-test.js https://example.com 5 ./results --verbose');
    }
}

/**
 * Script loader for performance metrics
 */
class MetricsScriptLoader {
    constructor(logger) {
        this.logger = logger;
        this.scriptPath = path.join(__dirname, '../Resources/performanceMetrics.js');
    }

    async load() {
        try {
            this.logger.debug(`Loading performance metrics script from: ${this.scriptPath}`);

            if (!fs.existsSync(this.scriptPath)) {
                this.logger.error(`Performance metrics script not found at: ${this.scriptPath}`);
                process.exit(EXIT_SCRIPT_NOT_FOUND);
            }

            const scriptContent = fs.readFileSync(this.scriptPath, 'utf8');
            this.logger.debug('Performance metrics script loaded successfully');
            return scriptContent;
        } catch (error) {
            this.logger.error(`Failed to load performance metrics script: ${error.message}`);
            process.exit(EXIT_SCRIPT_NOT_FOUND);
        }
    }
}

/**
 * Safari WebDriver manager
 */
class SafariDriverManager {
    constructor(logger) {
        this.logger = logger;
        this.driver = null;
    }

    async initialize() {
        try {
            this.logger.debug('Initializing Safari WebDriver');
            const options = new safari.Options();
            this.driver = await new Builder()
                .forBrowser('safari')
                .setSafariOptions(options)
                .build();
            this.logger.debug('Safari WebDriver initialized successfully');
            return this.driver;
        } catch (error) {
            this.logger.error(`Failed to initialize Safari WebDriver: ${error.message}`);
            this.logger.error('Ensure Safari\'s "Allow Remote Automation" is enabled in Develop menu');
            process.exit(EXIT_DRIVER_ERROR);
        }
    }

    async quit() {
        if (this.driver) {
            try {
                this.logger.debug('Closing Safari WebDriver');
                await this.driver.quit();
                this.driver = null;
            } catch (error) {
                this.logger.warn(`Error closing driver: ${error.message}`);
            }
        }
    }
}

/**
 * Performance test executor
 */
class PerformanceTestExecutor {
    constructor(config, driver, metricsScript) {
        this.config = config;
        this.driver = driver;
        this.metricsScript = metricsScript;
        this.logger = config.logger;
    }

    async waitForPageReady() {
        // Wait for body element
        await this.driver.wait(until.elementLocated(By.css('body')), this.config.timeout);

        // Wait for page to be completely loaded with navigation timing
        await this.driver.wait(async () => {
            try {
                const state = await this.driver.executeScript(`
                    return {
                        readyState: document.readyState,
                        hasNav: performance.getEntriesByType('navigation').length > 0,
                        loadEventEnd: performance.getEntriesByType('navigation')[0]?.loadEventEnd || 0
                    };
                `);
                return state.readyState === 'complete' && state.hasNav && state.loadEventEnd > 0;
            } catch (error) {
                this.logger.debug(`Waiting for page ready state: ${error.message}`);
                return false;
            }
        }, this.config.timeout);
    }

    async triggerLazyContent() {
        // Stability delay
        await this.sleep(this.config.stabilityDelay);

        // Scroll to trigger lazy-loaded content and LCP
        await this.driver.executeScript('window.scrollTo(0, 300);');
        await this.sleep(this.config.scrollDelay);

        // Scroll more to potentially trigger more layout shifts
        await this.driver.executeScript('window.scrollTo(0, 600);');
        await this.sleep(this.config.scrollDelay);
    }

    async collectMetrics() {
        const fullScript = this.metricsScript + '; return collectPerformanceMetrics();';

        for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
            try {
                const metrics = await this.driver.executeScript(fullScript);

                if (metrics && !metrics.error) {
                    return metrics;
                }

                if (metrics && metrics.error) {
                    this.logger.warn(`Metrics collection error (attempt ${attempt}): ${metrics.error}`);
                } else {
                    this.logger.debug(`Metrics returned null (attempt ${attempt})`);
                }

                if (attempt < MAX_RETRIES) {
                    await this.sleep(this.config.retryDelay);
                }
            } catch (error) {
                this.logger.warn(`Script execution error (attempt ${attempt}): ${error.message}`);
                if (attempt === MAX_RETRIES) {
                    throw error;
                }
                await this.sleep(this.config.retryDelay);
            }
        }

        throw new Error('Failed to collect metrics after all retry attempts');
    }

    async runSingleTest(url) {
        const testStart = Date.now();

        try {
            this.logger.debug(`Loading URL: ${url}`);
            await this.driver.get(url);

            this.logger.debug('Waiting for page to be ready');
            await this.waitForPageReady();

            this.logger.debug('Triggering lazy content');
            await this.triggerLazyContent();

            this.logger.debug('Collecting performance metrics');
            const metrics = await this.collectMetrics();

            return {
                success: true,
                url: url,
                timestamp: new Date().toISOString(),
                duration: Date.now() - testStart,
                metrics: metrics
            };
        } catch (error) {
            this.logger.error(`Test failed for ${url}: ${error.message}`);
            return {
                success: false,
                url: url,
                timestamp: new Date().toISOString(),
                duration: Date.now() - testStart,
                error: error.message,
                metrics: null
            };
        }
    }

    async sleep(ms) {
        return this.driver.sleep(ms);
    }
}

/**
 * Main test runner
 */
class SafariPerformanceTestRunner {
    constructor(config) {
        this.config = config;
        this.logger = config.logger;
        this.results = {
            testConfiguration: {
                url: config.url,
                iterations: config.iterations,
                browser: 'Safari',
                browserVersion: null,
                startTime: new Date().toISOString(),
                timeout: config.timeout,
                retries: MAX_RETRIES
            },
            iterations: []
        };
        this.isShuttingDown = false;
        this.setupShutdownHandlers();
    }

    setupShutdownHandlers() {
        const cleanup = async (signal) => {
            if (this.isShuttingDown) return;
            this.isShuttingDown = true;

            console.log(`\nReceived ${signal}, cleaning up...`);
            this.results.testConfiguration.interrupted = true;
            this.results.testConfiguration.endTime = new Date().toISOString();

            await this.saveResults();

            if (this.driverManager) {
                await this.driverManager.quit();
            }

            process.exit(EXIT_SUCCESS);
        };

        process.on('SIGINT', () => cleanup('SIGINT'));
        process.on('SIGTERM', () => cleanup('SIGTERM'));
    }

    async run() {
        this.logger.info('Starting Safari performance test');
        this.logger.info(`URL: ${this.config.url}`);
        this.logger.info(`Iterations: ${this.config.iterations}`);
        this.logger.info(`Output folder: ${this.config.outputFolder}`);

        // Load metrics script
        const scriptLoader = new MetricsScriptLoader(this.logger);
        const metricsScript = await scriptLoader.load();

        // Initialize driver
        this.driverManager = new SafariDriverManager(this.logger);
        const driver = await this.driverManager.initialize();

        // Get browser version
        try {
            const caps = await driver.getCapabilities();
            this.results.testConfiguration.browserVersion = caps.get('browserVersion') || 'unknown';
            this.logger.debug(`Safari version: ${this.results.testConfiguration.browserVersion}`);
        } catch (error) {
            this.logger.debug(`Could not determine Safari version: ${error.message}`);
        }

        // Create test executor
        const executor = new PerformanceTestExecutor(this.config, driver, metricsScript);

        // Run tests
        for (let i = 1; i <= this.config.iterations && !this.isShuttingDown; i++) {
            this.logger.info(`Running iteration ${i} of ${this.config.iterations}...`);

            const iterationResult = await executor.runSingleTest(this.config.url);
            iterationResult.iteration = i;
            this.results.iterations.push(iterationResult);

            if (iterationResult.success) {
                this.logger.info(`  ✓ Completed successfully (${iterationResult.duration}ms)`);
            } else {
                this.logger.error(`  ✗ Failed: ${iterationResult.error}`);
            }

            // Delay between iterations (except after last one)
            if (i < this.config.iterations && !this.isShuttingDown) {
                await executor.sleep(this.config.retryDelay);
            }
        }

        // Cleanup
        await this.driverManager.quit();

        // Save results
        this.results.testConfiguration.endTime = new Date().toISOString();
        await this.saveResults();

        // Report summary
        this.reportSummary();
    }

    async saveResults() {
        try {
            const outputJson = JSON.stringify(this.results, null, 2);

            // Console output (only in verbose mode)
            if (this.config.verbose) {
                console.log('\n=== Test Results (JSON) ===\n');
                console.log(outputJson);
            }

            // File output
            const timestamp = Date.now();
            const hostname = new URL(this.config.url).hostname;
            const sanitizedHost = hostname.replace(/[^a-z0-9]/gi, '_');
            const outputFile = path.join(
                this.config.outputFolder,
                `safari-performance-${sanitizedHost}-${timestamp}.json`
            );

            fs.writeFileSync(outputFile, outputJson);
            this.logger.info(`✓ Results saved to: ${outputFile}`);

            return outputFile;
        } catch (error) {
            this.logger.error(`Failed to save results: ${error.message}`);
            // Still output to console as fallback
            console.log('\n=== Test Results (JSON) ===\n');
            console.log(JSON.stringify(this.results, null, 2));
        }
    }

    reportSummary() {
        const successful = this.results.iterations.filter(r => r.success).length;
        const failed = this.results.iterations.length - successful;

        console.log('\n=== Test Summary ===');
        console.log(`Total iterations: ${this.results.iterations.length}`);
        console.log(`Successful: ${successful}`);
        console.log(`Failed: ${failed}`);

        if (successful > 0) {
            // Calculate average metrics for successful runs
            const metrics = this.results.iterations
                .filter(r => r.success && r.metrics)
                .map(r => r.metrics);

            if (metrics.length > 0) {
                const avgLoadComplete = metrics.reduce((sum, m) => sum + (m.loadComplete || 0), 0) / metrics.length;
                const avgFcp = metrics.reduce((sum, m) => sum + (m.fcp || 0), 0) / metrics.length;
                const avgTtfb = metrics.reduce((sum, m) => sum + (m.ttfb || 0), 0) / metrics.length;

                console.log('\nAverage metrics (successful runs):');
                console.log(`  Load Complete: ${Math.round(avgLoadComplete)}ms`);
                console.log(`  First Contentful Paint: ${Math.round(avgFcp)}ms`);
                console.log(`  Time to First Byte: ${Math.round(avgTtfb)}ms`);
            }
        }
    }
}

/**
 * Main entry point
 */
async function main() {
    try {
        const config = new TestConfiguration(process.argv.slice(2));
        const runner = new SafariPerformanceTestRunner(config);
        await runner.run();
    } catch (error) {
        console.error(`Unhandled error: ${error.message}`);
        if (error.stack) {
            console.error(error.stack);
        }
        process.exit(EXIT_RUNTIME_ERROR);
    }
}

// Run if executed directly
if (require.main === module) {
    main();
}

// Export for testing
module.exports = {
    TestConfiguration,
    MetricsScriptLoader,
    SafariDriverManager,
    PerformanceTestExecutor,
    SafariPerformanceTestRunner,
    Logger
};