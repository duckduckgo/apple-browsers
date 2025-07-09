import ContentFeature from '../content-feature';
import { getJsPerformanceMetrics } from './breakage-reporting/utils.js';

export default class BreakageReporting extends ContentFeature {
    init() {
        this.messaging.subscribe('getBreakageReportValues', () => {
            const jsPerformance = getJsPerformanceMetrics();
            const referrer = document.referrer;

            this.messaging.notify('breakageReportResult', {
                jsPerformance,
                referrer,
            });
        });
    }
}
