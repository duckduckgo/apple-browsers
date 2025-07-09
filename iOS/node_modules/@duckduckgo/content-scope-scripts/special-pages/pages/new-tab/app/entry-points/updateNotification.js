import { h } from 'preact';
import { UpdateNotificationConsumer } from '../update-notification/components/UpdateNotification.js';
import { UpdateNotificationProvider } from '../update-notification/UpdateNotificationProvider.js';

export function factory() {
    return (
        <div data-entry-point="updateNotification">
            <UpdateNotificationProvider>
                <UpdateNotificationConsumer />
            </UpdateNotificationProvider>
        </div>
    );
}
