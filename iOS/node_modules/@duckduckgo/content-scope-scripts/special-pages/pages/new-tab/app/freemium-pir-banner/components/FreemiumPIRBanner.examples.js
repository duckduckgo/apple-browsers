import { h } from 'preact';
import { noop } from '../../utils.js';
import { FreemiumPIRBanner } from './FreemiumPIRBanner.js';
import { freemiumPIRDataExamples } from '../mocks/freemiumPIRBanner.data.js';

/** @type {Record<string, {factory: () => import("preact").ComponentChild}>} */

export const freemiumPIRBannerExamples = {
    'freemiumPIR.onboarding': {
        factory: () => (
            <FreemiumPIRBanner
                message={freemiumPIRDataExamples.onboarding.content}
                dismiss={noop('freemiumPIRBanner_dismiss')}
                action={noop('freemiumPIRBanner_action')}
            />
        ),
    },
    'freemiumPIR.scan_results': {
        factory: () => (
            <FreemiumPIRBanner
                message={freemiumPIRDataExamples.scan_results.content}
                dismiss={noop('freemiumPIRBanner_dismiss')}
                action={noop('freemiumPIRBanner_action')}
            />
        ),
    },
};
