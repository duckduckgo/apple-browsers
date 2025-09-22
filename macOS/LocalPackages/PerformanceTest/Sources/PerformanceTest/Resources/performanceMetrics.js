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

(function() {
    try {
        // Wait for page to be fully loaded
        if (document.readyState !== 'complete') {
            return { error: 'Page not fully loaded' };
        }

        // Get navigation timing data
        const perfData = performance.getEntriesByType('navigation')[0];
        if (!perfData) {
            return { error: 'No navigation performance data available' };
        }

        // Get paint timing data
        const paintEntries = performance.getEntriesByType('paint');
        let firstContentfulPaint = null;

        for (const entry of paintEntries) {
            if (entry.name === 'first-contentful-paint') {
                firstContentfulPaint = entry.startTime;
            }
        }

        // Get largest contentful paint if available
        let largestContentfulPaint = null;
        if (window.PerformanceObserver && PerformanceObserver.supportedEntryTypes &&
            PerformanceObserver.supportedEntryTypes.includes('largest-contentful-paint')) {
            const lcpEntries = performance.getEntriesByType('largest-contentful-paint');
            if (lcpEntries.length > 0) {
                largestContentfulPaint = lcpEntries[lcpEntries.length - 1].startTime;
            }
        }

        // Calculate metrics
        const metrics = {
            loadComplete: perfData.loadEventEnd - perfData.fetchStart,
            firstContentfulPaint: firstContentfulPaint,
            largestContentfulPaint: largestContentfulPaint,
            timeToFirstByte: perfData.responseStart - perfData.fetchStart
        };

        return metrics;
    } catch (e) {
        return { error: 'JavaScript execution error: ' + e.message };
    }
})();