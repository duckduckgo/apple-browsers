import { h } from 'preact';
import { Centered } from '../components/Layout.js';
import { FreemiumPIRBannerConsumer } from '../freemium-pir-banner/components/FreemiumPIRBanner.js';
import { FreemiumPIRBannerProvider } from '../freemium-pir-banner/FreemiumPIRBannerProvider.js';

export function factory() {
    return (
        <Centered data-entry-point="freemiumPIRBanner">
            <FreemiumPIRBannerProvider>
                <FreemiumPIRBannerConsumer />
            </FreemiumPIRBannerProvider>
        </Centered>
    );
}
