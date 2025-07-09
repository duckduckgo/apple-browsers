import { h } from 'preact';
import { ComparisonTable } from './ComparisonTable';
import { SlideIn } from './Animation';

export function MakeDefaultStep() {
    return (
        <SlideIn>
            <ComparisonTable />
        </SlideIn>
    );
}
