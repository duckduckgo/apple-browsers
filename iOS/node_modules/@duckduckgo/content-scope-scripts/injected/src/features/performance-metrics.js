import ContentFeature from '../content-feature';
import { getJsPerformanceMetrics } from './breakage-reporting/utils.js';

export default class PerformanceMetrics extends ContentFeature {
    init() {
        this.messaging.subscribe('getVitals', () => {
            const vitals = getJsPerformanceMetrics();
            this.messaging.notify('vitalsResult', { vitals });
        });
    }
}
