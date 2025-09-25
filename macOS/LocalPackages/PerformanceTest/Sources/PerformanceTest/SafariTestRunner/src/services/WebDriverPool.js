/**
 * WebDriver connection pool for managing browser instances
 *
 * @module services/WebDriverPool
 */

const { Builder } = require('selenium-webdriver');
const safari = require('selenium-webdriver/safari');

/**
 * Connection pool for Safari WebDriver instances
 */
class WebDriverPool {
    constructor(logger, maxConnections = 3) {
        this.logger = logger;
        this.maxConnections = maxConnections;
        this.pool = [];
        this.activeConnections = new Set();
        this.totalCreated = 0;
        this.isShuttingDown = false;
    }

    /**
     * Acquire a WebDriver instance from the pool
     * @returns {Promise<Object>} WebDriver wrapper with driver and id
     */
    async acquire() {
        if (this.isShuttingDown) {
            throw new Error('WebDriver pool is shutting down');
        }

        // Try to get from pool first
        if (this.pool.length > 0) {
            const connection = this.pool.pop();
            this.activeConnections.add(connection);
            this.logger.debug(`Acquired driver from pool (ID: ${connection.id})`);
            return connection;
        }

        // Create new if under limit
        if (this.activeConnections.size < this.maxConnections) {
            const connection = await this._createNewDriver();
            this.activeConnections.add(connection);
            return connection;
        }

        // Wait for a connection to become available
        this.logger.debug('Waiting for available connection...');
        await this._waitForAvailableConnection();
        return this.acquire(); // Recursive call after wait
    }

    /**
     * Release a WebDriver instance back to the pool
     * @param {Object} connection - WebDriver connection to release
     */
    async release(connection) {
        if (!connection || !this.activeConnections.has(connection)) {
            this.logger.warn('Attempted to release invalid or already released connection');
            return;
        }

        this.activeConnections.delete(connection);

        // Check if driver is still valid
        try {
            await connection.driver.getCurrentUrl();

            // Clear session for reuse
            await this._clearSession(connection.driver);

            // Return to pool if not shutting down and pool not full
            if (!this.isShuttingDown && this.pool.length < this.maxConnections) {
                this.pool.push(connection);
                this.logger.debug(`Released driver to pool (ID: ${connection.id})`);
            } else {
                await this._closeDriver(connection);
            }
        } catch (error) {
            // Driver is dead, close it
            this.logger.debug(`Driver appears dead, closing (ID: ${connection.id})`);
            await this._closeDriver(connection);
        }
    }

    /**
     * Create a new WebDriver instance
     * @private
     */
    async _createNewDriver() {
        try {
            this.logger.debug('Creating new Safari WebDriver instance');

            const options = new safari.Options();
            const driver = await new Builder()
                .forBrowser('safari')
                .setSafariOptions(options)
                .build();

            this.totalCreated++;
            const connection = {
                id: `driver-${this.totalCreated}`,
                driver: driver,
                createdAt: Date.now(),
                usageCount: 0
            };

            this.logger.debug(`Created new driver (ID: ${connection.id})`);

            // Get and log capabilities
            try {
                const caps = await driver.getCapabilities();
                this.logger.debug(`Driver capabilities: ${caps.get('browserVersion') || 'unknown'}`);
            } catch (error) {
                this.logger.warn('Could not get driver capabilities');
            }

            return connection;
        } catch (error) {
            this.logger.error('Failed to create WebDriver', error);
            throw new Error(`Failed to create Safari WebDriver: ${error.message}`);
        }
    }

    /**
     * Clear session data for reuse
     * @private
     */
    async _clearSession(driver) {
        try {
            // Navigate to blank page to clear state
            await driver.get('about:blank');

            // Clear cookies
            await driver.manage().deleteAllCookies();

            // Clear local storage and session storage via JavaScript
            await driver.executeScript(`
                try { localStorage.clear(); } catch(e) {}
                try { sessionStorage.clear(); } catch(e) {}
            `);
        } catch (error) {
            this.logger.warn('Error clearing session', error);
            // Non-fatal, driver might still be usable
        }
    }

    /**
     * Close a driver connection
     * @private
     */
    async _closeDriver(connection) {
        try {
            this.logger.debug(`Closing driver (ID: ${connection.id})`);
            await connection.driver.quit();
        } catch (error) {
            this.logger.warn(`Error closing driver (ID: ${connection.id})`, error);
        }
    }

    /**
     * Wait for a connection to become available
     * @private
     */
    async _waitForAvailableConnection(maxWaitMs = 30000) {
        const startTime = Date.now();
        const checkInterval = 100;

        while (Date.now() - startTime < maxWaitMs) {
            if (this.pool.length > 0 || this.activeConnections.size < this.maxConnections) {
                return;
            }
            await new Promise(resolve => setTimeout(resolve, checkInterval));
        }

        throw new Error('Timeout waiting for available WebDriver connection');
    }

    /**
     * Get pool statistics
     */
    getStats() {
        return {
            poolSize: this.pool.length,
            activeConnections: this.activeConnections.size,
            totalCreated: this.totalCreated,
            maxConnections: this.maxConnections
        };
    }

    /**
     * Shutdown the pool and close all connections
     */
    async shutdown() {
        this.isShuttingDown = true;
        this.logger.info('Shutting down WebDriver pool');

        // Close pooled connections
        const pooledConnections = [...this.pool];
        this.pool = [];

        for (const connection of pooledConnections) {
            await this._closeDriver(connection);
        }

        // Close active connections
        const activeConnections = [...this.activeConnections];
        this.activeConnections.clear();

        for (const connection of activeConnections) {
            await this._closeDriver(connection);
        }

        this.logger.info('WebDriver pool shutdown complete');
    }

    /**
     * Check if pool is healthy
     */
    isHealthy() {
        return !this.isShuttingDown && (this.pool.length > 0 || this.activeConnections.size < this.maxConnections);
    }
}

module.exports = WebDriverPool;