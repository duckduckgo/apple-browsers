/**
 * @returns array of performance metrics
 */
export function getJsPerformanceMetrics() {
    const paintResources = performance.getEntriesByType('paint');
    const firstPaint = paintResources.find((entry) => entry.name === 'first-contentful-paint');
    return firstPaint ? [firstPaint.startTime] : [];
}
