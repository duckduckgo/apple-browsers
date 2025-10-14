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

        // Note: LCP is not supported in Safari/WebKit - always 0
        const largestContentfulPaint = 0;

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

                // Network timing metrics
                ttfb: (typeof navigation.responseStart === 'number' && typeof navigation.fetchStart === 'number')
                    ? (navigation.responseStart - navigation.fetchStart)
                    : NOT_AVAILABLE,
                responseTime: (typeof navigation.responseEnd === 'number' && typeof navigation.responseStart === 'number')
                    ? (navigation.responseEnd - navigation.responseStart)
                    : NOT_AVAILABLE,
                serverTime: (typeof navigation.responseStart === 'number' && typeof navigation.requestStart === 'number')
                    ? (navigation.responseStart - navigation.requestStart)
                    : NOT_AVAILABLE,

                // Size metrics - return 0 as legitimate value (not N/A)
                transferSize: typeof navigation.transferSize === 'number' ? navigation.transferSize : 0,
                encodedBodySize: typeof navigation.encodedBodySize === 'number' ? navigation.encodedBodySize : 0,
                decodedBodySize: typeof navigation.decodedBodySize === 'number' ? navigation.decodedBodySize : 0,

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
