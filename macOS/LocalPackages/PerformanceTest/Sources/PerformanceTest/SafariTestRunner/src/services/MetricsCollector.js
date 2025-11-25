/**
 * Service for collecting performance metrics
 *
 * @module services/MetricsCollector
 */

const { METRICS_SCRIPT } = require('../constants/metricsScript');

/**
 * Collector for performance metrics using the shared script
 */
class MetricsCollector {
    constructor(logger) {
        this.logger = logger;
        this.metricsScript = null;
    }

    /**
     * Load the performance metrics script
     * @returns {Promise<string>} Script content
     */
    async loadScript() {
        if (this.metricsScript) {
            return this.metricsScript;
        }

        try {
            this.logger.debug('Loading metrics script from bundled module');

            // Use the imported metrics script constant
            this.metricsScript = METRICS_SCRIPT;

            if (!this.metricsScript) {
                throw new Error('Metrics script constant is empty');
            }

            this.logger.debug('Metrics script loaded successfully');

            return this.metricsScript;
        } catch (error) {
            this.logger.error('Failed to load metrics script', error);
            throw new Error(`Failed to load performance metrics script: ${error.message}`);
        }
    }

    /**
     * Prepare script for execution
     * @returns {string} Prepared script
     */
    prepareScript() {
        if (!this.metricsScript) {
            throw new Error('Metrics script not loaded. Call loadScript() first');
        }

        // Add the function call to the script
        return `${this.metricsScript}; return collectPerformanceMetrics();`;
    }

    /**
     * Validate collected metrics
     * @param {Object} metrics - Collected metrics
     * @returns {boolean} Validation result
     */
    validateMetrics(metrics) {
        if (!metrics) {
            this.logger.warn('Metrics is null or undefined');
            return false;
        }

        if (metrics.error) {
            this.logger.warn(`Metrics contains error: ${metrics.error}`);
            return false;
        }

        // Check for essential metrics
        const requiredFields = ['loadComplete', 'domComplete', 'ttfb'];
        for (const field of requiredFields) {
            if (typeof metrics[field] === 'undefined') {
                this.logger.warn(`Missing required metric: ${field}`);
                return false;
            }
        }

        return true;
    }

    /**
     * Process raw metrics
     * @param {Object} metrics - Raw metrics
     * @returns {Object} Processed metrics
     */
    processMetrics(metrics) {
        if (!this.validateMetrics(metrics)) {
            return null;
        }

        // Return metrics as-is, but could add processing here if needed
        return {
            ...metrics,
            _processed: true,
            _timestamp: new Date().toISOString()
        };
    }

    /**
     * Get script information
     * @returns {Object} Script information
     */
    getScriptInfo() {
        return {
            source: 'bundled module',
            loaded: !!this.metricsScript,
            size: this.metricsScript ? this.metricsScript.length : 0
        };
    }
}

module.exports = MetricsCollector;