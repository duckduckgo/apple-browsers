import { h } from 'preact';
import { Centered } from '../components/Layout.js';
import { RMFConsumer } from '../remote-messaging-framework/components/RemoteMessagingFramework.js';
import { RMFProvider } from '../remote-messaging-framework/RMFProvider.js';

export function factory() {
    return (
        <Centered data-entry-point="rmf">
            <RMFProvider>
                <RMFConsumer />
            </RMFProvider>
        </Centered>
    );
}
