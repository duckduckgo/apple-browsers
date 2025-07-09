import { h } from 'preact';
import { Centered } from '../components/Layout.js';
import { ProtectionsCustomized } from '../protections/components/ProtectionsCustomized.js';

export function factory() {
    return (
        <Centered data-entry-point="protections">
            <ProtectionsCustomized></ProtectionsCustomized>
        </Centered>
    );
}
