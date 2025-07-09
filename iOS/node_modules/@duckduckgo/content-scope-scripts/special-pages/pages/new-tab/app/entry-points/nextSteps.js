import { h } from 'preact';
import { Centered } from '../components/Layout.js';
import { NextStepsCustomized } from '../next-steps/NextSteps.js';

export function factory() {
    return (
        <Centered data-entry-point="nextSteps">
            <NextStepsCustomized />
        </Centered>
    );
}
