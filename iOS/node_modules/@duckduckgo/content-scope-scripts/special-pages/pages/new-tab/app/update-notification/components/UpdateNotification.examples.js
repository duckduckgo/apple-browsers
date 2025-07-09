import { h } from 'preact';
import { UpdateNotification } from './UpdateNotification.js';
import { noop } from '../../utils.js';

export const updateNotificationExamples = {
    'updateNotification.empty': {
        factory: () => {
            return <UpdateNotification notes={[]} version={'1.2.3'} dismiss={noop('dismiss!')} />;
        },
    },
    'updateNotification.populated': {
        factory: () => {
            return <UpdateNotification notes={['Bug Fixed and Updates']} version={'1.2.3'} dismiss={noop('dismiss!')} />;
        },
    },
};
