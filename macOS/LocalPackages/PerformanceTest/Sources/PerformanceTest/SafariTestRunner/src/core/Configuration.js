/**
 * Configuration management for performance tests
 *
 * @module core/Configuration
 */

const { URL } = require('url');
const fs = require('fs');
const path = require('path');

/**
 * Configuration class for managing test settings
 */
class Configuration {
    static DEFAULT_VALUES = {
        iterations: 1,
        outputFolder: null,  // null = console output only
        timeout: 30000,
        retryDelay: 500,
        scrollDelay: 500,
        stabilityDelay: 500,
        sessionRestartDelay: 1000,  // Delay after quitting session before restart
        maxRetries: 3,
        verbose: false
    };

    static LIMITS = {
        minIterations: 1,
        maxIterations: 50
    };

    constructor(options = {}) {
        this._validateAndSetOptions(options);
    }

    /**
     * Validate and set configuration options
     * @private
     */
    _validateAndSetOptions(options) {

        // Input validation
        this.url = this._validateUrl(options.url);        
        this.iterations = this._validateIterations(options.iterations);
        this.outputFolder = this._validateOutputFolder(options.outputFolder);

        // Timing Configs
        this.timeout = options.timeout || Configuration.DEFAULT_VALUES.timeout;
        this.retryDelay = options.retryDelay || Configuration.DEFAULT_VALUES.retryDelay;
        this.scrollDelay = options.scrollDelay || Configuration.DEFAULT_VALUES.scrollDelay;
        this.stabilityDelay = options.stabilityDelay || Configuration.DEFAULT_VALUES.stabilityDelay;
        this.sessionRestartDelay = options.sessionRestartDelay || Configuration.DEFAULT_VALUES.sessionRestartDelay;
        this.maxRetries = options.maxRetries || Configuration.DEFAULT_VALUES.maxRetries;

        // Set flags
        this.verbose = options.verbose || Configuration.DEFAULT_VALUES.verbose;
    }

    /**
     * Validate URL
     * @private
     */
    _validateUrl(url) {
        if (!url) {
            throw new Error('URL is required');
        }

        try {
            const parsedUrl = new URL(url);
            if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
                throw new Error(`Invalid protocol: ${parsedUrl.protocol}`);
            }
            return url;
        } catch (error) {
            throw new Error(`Invalid URL: ${url}. ${error.message}`);
        }
    }

    /**
     * Validate iterations count
     * @private
     */
    _validateIterations(iterations) {
        const value = parseInt(iterations) || Configuration.DEFAULT_VALUES.iterations;

        if (isNaN(value) || value < Configuration.LIMITS.minIterations || value > Configuration.LIMITS.maxIterations) {
            throw new Error(
                `Invalid iterations: ${iterations}. Must be between ${Configuration.LIMITS.minIterations} and ${Configuration.LIMITS.maxIterations}`
            );
        }

        return value;
    }

    /**
     * Validate and prepare output folder
     * @private
     */
    _validateOutputFolder(folder) {
        // If no folder provided or explicitly set to null/empty, return null (console output)
        if (!folder || folder === '' || folder === 'none' || folder === 'console') {
            return null;
        }

        const outputFolder = folder || Configuration.DEFAULT_VALUES.outputFolder;

        try {
            // Expand tilde for home directory
            const expandedPath = outputFolder.replace(/^~/, process.env.HOME || process.env.USERPROFILE || '');
            const resolvedPath = path.resolve(expandedPath);

            if (!fs.existsSync(resolvedPath)) {
                fs.mkdirSync(resolvedPath, { recursive: true });
            }

            // Verify it's writable
            fs.accessSync(resolvedPath, fs.constants.W_OK);
            return resolvedPath;
        } catch (error) {
            throw new Error(`Output folder error: ${outputFolder}. ${error.message}`);
        }
    }

    /**
     * Get configuration as plain object
     * @returns {Object} Configuration object
     */
    toObject() {
        return {
            url: this.url,
            iterations: this.iterations,
            outputFolder: this.outputFolder,
            timeout: this.timeout,
            retryDelay: this.retryDelay,
            scrollDelay: this.scrollDelay,
            stabilityDelay: this.stabilityDelay,
            sessionRestartDelay: this.sessionRestartDelay,
            maxRetries: this.maxRetries,
            verbose: this.verbose
        };
    }

    /**
     * Create configuration from command line arguments
     * @static
     */
    static fromCommandLine(args) {
        if (args.length < 1) {
            throw new Error('URL is required');
        }

        return new Configuration({
            url: args[0],
            iterations: args[1],
            outputFolder: args[2],
            verbose: args.includes('--verbose') || args.includes('-v')
        });
    }
}

module.exports = Configuration;