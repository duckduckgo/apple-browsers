/**
 * Service for managing test results
 *
 * @module services/ResultsManager
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
     * Save results to file or output to console
     * @returns {Promise<string|null>} Output file path or null if console output
     */
    async save() {
        const jsonContent = JSON.stringify(this.results, null, 2);

        // If no output folder specified, output to console only
        if (!this.config.outputFolder || this.config.outputFolder === '.' || this.config.outputFolder === '') {
            console.log('\n=== Test Results ===\n');
            console.log(jsonContent);
            console.log('\n===================\n');
            this.logger.info('Results output to console (no output folder specified)');
            return null;
        }

        // Otherwise, save to file
        try {
            const outputPath = this._generateOutputPath();
            fs.writeFileSync(outputPath, jsonContent);
            this.logger.info(`Results saved to: ${outputPath}`);
            return outputPath;
        } catch (error) {
            this.logger.error('Failed to save results to file', error);
            // Fallback: output to console
            console.log('\n=== Test Results (Fallback due to save error) ===\n');
            console.log(jsonContent);
            throw error;
        }
    }

    /**
     * Generate output file path with security validations
     * @private
     */
    _generateOutputPath() {
        const timestamp = Date.now();
        const hostname = new URL(this.config.url).hostname;

        // Comprehensive sanitization to prevent path traversal
        const sanitizedHost = hostname
            .replace(/[^a-z0-9.-]/gi, '_')  // Allow dots and hyphens
            .replace(/\.{2,}/g, '_')         // Replace consecutive dots
            .replace(/^\.+|\.+$/g, '')       // Remove leading/trailing dots
            .substring(0, 100);              // Limit length

        // Validate filename doesn't contain path separators
        const filename = `safari-performance-${sanitizedHost}-${timestamp}.json`;
        if (filename.includes('/') || filename.includes('\\') || filename.includes('..')) {
            throw new Error('Invalid filename generated');
        }

        // Ensure output folder is absolute and normalized
        const outputFolder = path.resolve(this.config.outputFolder);

        // Verify the resolved path is within the intended directory
        const outputPath = path.join(outputFolder, filename);
        const normalizedOutput = path.normalize(outputPath);

        if (!normalizedOutput.startsWith(outputFolder)) {
            throw new Error('Security error: Output path traversal detected');
        }

        return normalizedOutput;
    }

    /**
     * Get summary statistics
     * @returns {Object} Summary statistics
     */
    getSummary() {
        const successful = this.results.iterations.filter(r => r.success);
        const failed = this.results.iterations.filter(r => !r.success);

        return {
            total: this.results.iterations.length,
            successful: successful.length,
            failed: failed.length,
            successRate: this.results.iterations.length > 0
                ? successful.length / this.results.iterations.length
                : 0
        };
    }

    /**
     * Print summary to console
     */
    printSummary() {
        const successful = this.results.iterations.filter(r => r.success).length;
        const failed = this.results.iterations.filter(r => !r.success).length;
        const total = this.results.iterations.length;
        const successRate = total > 0 ? (successful / total * 100).toFixed(1) : 0;

        console.log('\n=== Test Summary ===');
        console.log(`Total iterations: ${total}`);
        console.log(`Successful: ${successful}`);
        console.log(`Failed: ${failed}`);
        console.log(`Success rate: ${successRate}%`);

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