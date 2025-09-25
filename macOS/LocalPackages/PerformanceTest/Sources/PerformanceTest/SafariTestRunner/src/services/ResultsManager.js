/**
 * Service for managing test results
 *
 * @module services/ResultsManager
 * @copyright 2024 DuckDuckGo
 * @license Apache-2.0
 */

const fs = require('fs');
const path = require('path');
const { URL } = require('url');

/**
 * Manager for test results and reporting
 */
class ResultsManager {
    constructor(configuration, logger) {
        this.config = configuration;
        this.logger = logger;
        this.results = this._initializeResults();
    }

    /**
     * Initialize results structure
     * @private
     */
    _initializeResults() {
        return {
            testConfiguration: {
                url: this.config.url,
                iterations: this.config.iterations,
                browser: 'Safari',
                browserVersion: null,
                platform: process.platform,
                startTime: new Date().toISOString(),
                timeout: this.config.timeout,
                maxRetries: this.config.maxRetries
            },
            iterations: [],
            metadata: {
                interrupted: false,
                endTime: null
            }
        };
    }

    /**
     * Set browser version
     * @param {string} version - Browser version
     */
    setBrowserVersion(version) {
        this.results.testConfiguration.browserVersion = version;
    }

    /**
     * Add iteration result
     * @param {Object} result - Iteration result
     * @param {number} iterationNumber - Iteration number
     */
    addIterationResult(result, iterationNumber) {
        this.results.iterations.push({
            iteration: iterationNumber,
            ...result
        });
    }

    /**
     * Mark test as interrupted
     */
    markInterrupted() {
        this.results.metadata.interrupted = true;
    }

    /**
     * Finalize results
     */
    finalize() {
        this.results.metadata.endTime = new Date().toISOString();
    }

    /**
     * Save results to file
     * @returns {Promise<string>} Output file path
     */
    async save() {
        try {
            const outputPath = this._generateOutputPath();
            const jsonContent = JSON.stringify(this.results, null, 2);

            fs.writeFileSync(outputPath, jsonContent);
            this.logger.info(`Results saved to: ${outputPath}`);

            return outputPath;
        } catch (error) {
            this.logger.error('Failed to save results', error);
            // Fallback: output to console
            console.log('\n=== Test Results (Fallback) ===\n');
            console.log(JSON.stringify(this.results, null, 2));
            throw error;
        }
    }

    /**
     * Generate output file path
     * @private
     */
    _generateOutputPath() {
        const timestamp = Date.now();
        const hostname = new URL(this.config.url).hostname;
        const sanitizedHost = hostname.replace(/[^a-z0-9]/gi, '_');
        const filename = `safari-performance-${sanitizedHost}-${timestamp}.json`;

        return path.join(this.config.outputFolder, filename);
    }

    /**
     * Get summary statistics
     * @returns {Object} Summary statistics
     */
    getSummary() {
        const successful = this.results.iterations.filter(r => r.success);
        const failed = this.results.iterations.filter(r => !r.success);

        const summary = {
            total: this.results.iterations.length,
            successful: successful.length,
            failed: failed.length,
            successRate: successful.length / this.results.iterations.length
        };

        // Calculate average metrics for successful runs
        if (successful.length > 0) {
            const metrics = successful
                .filter(r => r.metrics)
                .map(r => r.metrics);

            if (metrics.length > 0) {
                summary.averageMetrics = this._calculateAverageMetrics(metrics);
            }
        }

        return summary;
    }

    /**
     * Calculate average metrics
     * @private
     */
    _calculateAverageMetrics(metricsArray) {
        const averages = {};
        const numericFields = ['loadComplete', 'domComplete', 'fcp', 'ttfb', 'domInteractive'];

        for (const field of numericFields) {
            const values = metricsArray
                .map(m => m[field])
                .filter(v => typeof v === 'number' && !isNaN(v));

            if (values.length > 0) {
                const sum = values.reduce((a, b) => a + b, 0);
                averages[field] = Math.round(sum / values.length);
            }
        }

        return averages;
    }

    /**
     * Print summary to console
     */
    printSummary() {
        const summary = this.getSummary();

        console.log('\n=== Test Summary ===');
        console.log(`Total iterations: ${summary.total}`);
        console.log(`Successful: ${summary.successful}`);
        console.log(`Failed: ${summary.failed}`);
        console.log(`Success rate: ${(summary.successRate * 100).toFixed(1)}%`);

        if (this.results.metadata.interrupted) {
            console.log('\n⚠️  Test was interrupted');
        }
    }

    /**
     * Get results object
     * @returns {Object} Results
     */
    getResults() {
        return this.results;
    }
}

module.exports = ResultsManager;