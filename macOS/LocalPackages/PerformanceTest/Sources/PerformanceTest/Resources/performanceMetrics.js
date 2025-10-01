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

// Constants for unavailable metrics
const NOT_AVAILABLE = 'N/A';

function collectPerformanceMetrics() {
   try {
        if (document.readyState !== 'complete') {
            return null;
        }

        const navigation = performance.getEntriesByType('navigation')[0];
        const paint = performance.getEntriesByType('paint');
        const resources = performance.getEntriesByType('resource');

        // Find FCP
        const fcp = paint.find(p => p.name === 'first-contentful-paint');

        // Note: LCP is not supported in Safari/WebKit - always null
        const largestContentfulPaint = null;

        // Calculate total resource sizes
        const totalResourceSize = resources.reduce((sum, r) => sum + (r.transferSize || 0), 0);

        if (navigation) {
            // Calculate common metrics once
            const timeToFirstByte = (navigation.responseStart - navigation.fetchStart) || NOT_AVAILABLE;
            const serverTime = (navigation.responseStart - navigation.requestStart) || NOT_AVAILABLE;

            return {
                // Core timing metrics (in milliseconds)
                loadComplete: navigation.loadEventEnd - navigation.fetchStart,
                domComplete: navigation.domComplete - navigation.fetchStart,
                domContentLoaded: navigation.domContentLoadedEventEnd - navigation.fetchStart,
                domInteractive: navigation.domInteractive - navigation.fetchStart,

                // Paint metrics (both naming conventions for compatibility)
                fcp: fcp ? fcp.startTime : 0,
                firstContentfulPaint: fcp ? fcp.startTime : null,
                largestContentfulPaint: largestContentfulPaint,
                // Note: CLS is not supported in Safari WebDriver
                cumulativeLayoutShift: null,

                // Network metrics (both naming conventions for compatibility)
                // Safari WebDriver doesn't provide fetchStart/requestStart properly, so these will be 0
                ttfb: timeToFirstByte,
                timeToFirstByte: timeToFirstByte,
                responseTime: navigation.responseEnd - navigation.responseStart,
                serverTime: serverTime,
                transferSize: navigation.transferSize || 0,
                encodedBodySize: navigation.encodedBodySize || 0,
                decodedBodySize: navigation.decodedBodySize || 0,

                // Resource metrics
                resourceCount: resources.length,
                totalResourcesSize: totalResourceSize,

                // TTI approximation
                tti: navigation.domInteractive - navigation.fetchStart,

                // Additional metadata
                protocol: navigation.nextHopProtocol || NOT_AVAILABLE,
               redirectCount: navigation.redirectCount || 0,
                navigationType: navigation.type || 'navigate'
            };
        }

        return null;
    } catch (e) {
        return { error: 'JavaScript execution error: ' + e.message };
    }
}
