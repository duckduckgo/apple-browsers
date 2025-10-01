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

// Use a global variable to persist CLS across script executions
if (typeof window.__cumulativeLayoutShift === 'undefined') {
    window.__cumulativeLayoutShift = 0;

    // Check for CLS support and start observing
    if (typeof PerformanceObserver !== 'undefined' && PerformanceObserver.supportedEntryTypes.includes('layout-shift')) {
        const observer = new PerformanceObserver((list) => {
            for (const entry of list.getEntries()) {
                if (!entry.hadRecentInput) {
                    window.__cumulativeLayoutShift += entry.value;
                }
            }
        });
        observer.observe({ type: 'layout-shift', buffered: true });
    }
}


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

        // Get largest contentful paint if available
        let largestContentfulPaint = null;
        if (window.PerformanceObserver && PerformanceObserver.supportedEntryTypes &&
            PerformanceObserver.supportedEntryTypes.includes('largest-contentful-paint')) {
            const lcpEntries = performance.getEntriesByType('largest-contentful-paint');
            if (lcpEntries.length > 0) {
                largestContentfulPaint = lcpEntries[lcpEntries.length - 1].startTime;
            }
        }

        // Calculate total resource sizes
        const totalResourceSize = resources.reduce((sum, r) => sum + (r.transferSize || 0), 0);

        if (navigation) {
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
                cumulativeLayoutShift: window.__cumulativeLayoutShift,

                // Network metrics (both naming conventions for compatibility)
                // Safari WebDriver doesn't provide fetchStart/requestStart properly, so these will be 0

                ttfb: (navigation.responseStart - navigation.fetchStart) || 'N/A',
                timeToFirstByte: (navigation.responseStart - navigation.fetchStart) || 'N/A',
                responseTime: navigation.responseEnd - navigation.responseStart,

                serverTime: (navigation.responseStart - navigation.requestStart) || 'N/A',
                // Size metrics (in bytes)
                transferSize: navigation.transferSize || 0,
                encodedBodySize: navigation.encodedBodySize || 0,
                decodedBodySize: navigation.decodedBodySize || 0,

                // Resource metrics
                resourceCount: resources.length,
                totalResourcesSize: totalResourceSize,

                // TTI approximation
                tti: navigation.domInteractive - navigation.fetchStart,

                // Additional metadata
                protocol: navigation.nextHopProtocol || 'N/A',
               redirectCount: navigation.redirectCount || 0,
                navigationType: navigation.type || 'navigate'
            };
        }

        return null;
    } catch (e) {
        return { error: 'JavaScript execution error: ' + e.message };
    }
}
