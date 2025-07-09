import { h } from 'preact';
import { Centered } from '../components/Layout.js';
import { OmnibarCustomized } from '../omnibar/components/OmnibarCustomized.js';

export function factory() {
    return (
        <Centered data-entry-point="omnibar">
            <OmnibarCustomized />
        </Centered>
    );
}
