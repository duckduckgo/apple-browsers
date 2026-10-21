/**
 * Logger utility for consistent logging across the application
 *
 * @module utils/Logger
 */

class Logger {
    constructor(options = {}) {
        this.verbose = options.verbose || false;
        this.silent = options.silent || false;
        this.prefix = options.prefix || '';
    }

    /**
     * Log info level message
     * @param {string} message - Message to log
     * @param {Object} meta - Additional metadata
     */
    info(message, meta = {}) {
        if (!this.silent) {
            const logMessage = this._formatMessage('INFO', message);
            console.log(logMessage, this._formatMeta(meta));
        }
    }

    /**
     * Log error level message
     * @param {string} message - Message to log
     * @param {Error|Object} error - Error object or metadata
     */
    error(message, error = {}) {
        if (!this.silent) {
            const logMessage = this._formatMessage('ERROR', message);
            if (error instanceof Error) {
                console.error(logMessage, '\n', error.stack || error.message);
            } else {
                console.error(logMessage, this._formatMeta(error));
            }
        }
    }

    /**
     * Log warning level message
     * @param {string} message - Message to log
     * @param {Object} meta - Additional metadata
     */
    warn(message, meta = {}) {
        if (!this.silent) {
            const logMessage = this._formatMessage('WARN', message);
            console.warn(logMessage, this._formatMeta(meta));
        }
    }

    /**
     * Log debug level message (only in verbose mode)
     * @param {string} message - Message to log
     * @param {Object} meta - Additional metadata
     */
    debug(message, meta = {}) {
        if (this.verbose && !this.silent) {
            const logMessage = this._formatMessage('DEBUG', message);
            console.log(logMessage, this._formatMeta(meta));
        }
    }

    /**
     * Format message with level and timestamp
     * @private
     */
    _formatMessage(level, message) {
        // Use simple format for better Swift parsing
        const prefix = this.prefix ? `[${this.prefix}] ` : '';
        return `[${level}] ${prefix}${message}`;
    }

    /**
     * Format metadata for logging
     * @private
     */
    _formatMeta(meta) {
        if (Object.keys(meta).length === 0) {
            return '';
        }
        return JSON.stringify(meta, null, 2);
    }

    /**
     * Create a child logger with additional prefix
     * @param {string} prefix - Additional prefix for child logger
     * @returns {Logger} New logger instance
     */
    child(prefix) {
        return new Logger({
            verbose: this.verbose,
            silent: this.silent,
            prefix: this.prefix ? `${this.prefix}:${prefix}` : prefix
        });
    }
}

module.exports = Logger;