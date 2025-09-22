//
//  performanceMetrics.js
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

/**
 * Collects performance metrics from the browser's Performance API
 * @returns {Object} Performance metrics object with timing and resource information
 */
function collectPerformanceMetrics() {
    // Get navigation timing data
    const navigationEntry = performance.getEntriesByType('navigation')[0];
    if (!navigationEntry) {
        return { error: 'No navigation timing data available' };
    }

    // Paint timing
    const paintEntries = performance.getEntriesByType('paint');
    const firstPaint = paintEntries.find(entry => entry.name === 'first-paint');
    const firstContentfulPaint = paintEntries.find(entry => entry.name === 'first-contentful-paint');

    // LCP (If implemented)
    const lcpEntries = performance.getEntriesByType('largest-contentful-paint');
    const largestContentfulPaint = lcpEntries.length > 0 ? lcpEntries[lcpEntries.length - 1] : null;

    // Other Metrics
    const metrics = {
        // Time to First Byte
        timeToFirstByte: navigationEntry.responseStart - navigationEntry.fetchStart,

        // FCP
        firstContentfulPaint: firstContentfulPaint ? firstContentfulPaint.startTime : null,

        // LCP
        largestContentfulPaint: largestContentfulPaint ? largestContentfulPaint.startTime : null,

        // DOM metrics
        domInteractive: navigationEntry.domInteractive - navigationEntry.fetchStart,
        domContentLoaded: navigationEntry.domContentLoadedEventEnd - navigationEntry.fetchStart,
        domComplete: navigationEntry.domComplete - navigationEntry.fetchStart,

        // Load complete time
        loadComplete: navigationEntry.loadEventEnd - navigationEntry.fetchStart,

        // Network times
        dnsLookupTime: navigationEntry.domainLookupEnd - navigationEntry.domainLookupStart,
        tcpConnectionTime: navigationEntry.connectEnd - navigationEntry.connectStart,
        secureConnectionTime: navigationEntry.secureConnectionStart > 0 ?
            navigationEntry.connectEnd - navigationEntry.secureConnectionStart : 0,

        // Response metrics
        responseTime: navigationEntry.responseEnd - navigationEntry.responseStart,

        // Transfer sizes
        transferSize: navigationEntry.transferSize || 0,
        encodedBodySize: navigationEntry.encodedBodySize || 0,
        decodedBodySize: navigationEntry.decodedBodySize || 0,

        // Server timing
        serverTiming: extractServerTiming(navigationEntry),

        // Resource count
        resourceCount: performance.getEntriesByType('resource').length,

        // Additional metadata
        protocol: navigationEntry.nextHopProtocol || 'unknown',
        redirectCount: navigationEntry.redirectCount || 0,
        navigationType: navigationEntry.type || 'navigate'
    };

    return metrics;
}

/**
 * Extracts server timing information from navigation entry
 * @param {PerformanceNavigationTiming} navigationEntry - The navigation timing entry
 * @returns {number} Server processing time in milliseconds
 */
function extractServerTiming(navigationEntry) {
    // If serverTiming is available, calculate total server time
    if (navigationEntry.serverTiming && navigationEntry.serverTiming.length > 0) {
        return navigationEntry.serverTiming.reduce((total, entry) => {
            return total + (entry.duration || 0);
        }, 0);
    }

    // Fallback: estimate server time from response timings
    // This is the time between request sent and first byte received
    return navigationEntry.responseStart - navigationEntry.requestStart;
}

// Export the main function for WebKit to call
collectPerformanceMetrics();