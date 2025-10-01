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

const NOT_AVAILABLE = 'N/A';
const DOCUMENT_STATE_COMPLETE = 'complete';
const NAVIGATION_TYPE_NAVIGATE = 'navigate';

// Performance API
const ENTRY_TYPE_NAVIGATION = 'navigation';
const ENTRY_TYPE_PAINT = 'paint';
const ENTRY_TYPE_RESOURCE = 'resource';
const PAINT_NAME_FCP = 'first-contentful-paint';



function collectPerformanceMetrics() {
   try {
        if (document.readyState !== DOCUMENT_STATE_COMPLETE) {
            return null;
        }

        const navigation = performance.getEntriesByType(ENTRY_TYPE_NAVIGATION)[0];
        const paint = performance.getEntriesByType(ENTRY_TYPE_PAINT);
        const resources = performance.getEntriesByType(ENTRY_TYPE_RESOURCE);

        // Find FCP
        const fcp = paint.find(p => p.name === PAINT_NAME_FCP);

        // Note: LCP is not supported in Safari/WebKit - always null
        const largestContentfulPaint = null;

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
                // Note: CLS is not supported in Safari WebDriver
                cumulativeLayoutShift: null,

                // Network metrics
                // Note: Safari WebDriver doesn't provide these timing/size properties in automation context
                // They return 0, so we mark them as N/A. These work in native WKWebView but not via WebDriver.
                ttfb: (navigation.responseStart && navigation.fetchStart && navigation.responseStart !== navigation.fetchStart)
                    ? (navigation.responseStart - navigation.fetchStart)
                    : NOT_AVAILABLE,
                responseTime: (navigation.responseEnd && navigation.responseStart && navigation.responseEnd > navigation.responseStart)
                    ? (navigation.responseEnd - navigation.responseStart)
                    : NOT_AVAILABLE,
                serverTime: (navigation.responseStart && navigation.requestStart && navigation.responseStart !== navigation.requestStart)
                    ? (navigation.responseStart - navigation.requestStart)
                    : NOT_AVAILABLE,
                transferSize: navigation.transferSize || NOT_AVAILABLE,
                encodedBodySize: navigation.encodedBodySize || NOT_AVAILABLE,
                decodedBodySize: navigation.decodedBodySize || NOT_AVAILABLE,

                // Resource metrics
                resourceCount: resources.length,
                totalResourcesSize: totalResourceSize,

                // TTI approximation
                tti: navigation.domInteractive - navigation.fetchStart,

                // Additional metadata
                protocol: navigation.nextHopProtocol || NOT_AVAILABLE,
               redirectCount: navigation.redirectCount || 0,
                navigationType: navigation.type || NAVIGATION_TYPE_NAVIGATE
            };
        }

        return null;
    } catch (e) {
        return { error: 'JavaScript execution error: ' + e.message };
    }
}
