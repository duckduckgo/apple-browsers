import { h } from 'preact';
import { noop } from '../../utils.js';
import { RemoteMessagingFramework } from './RemoteMessagingFramework.js';
import { rmfDataExamples } from '../mocks/rmf.data.js';

/** @type {Record<string, {factory: () => import("preact").ComponentChild}>} */

export const RMFExamples = {
    'rmf.small': {
        factory: () => <RemoteMessagingFramework message={rmfDataExamples.small.content} dismiss={noop('rmf_dismiss')} />,
    },
    'rmf.medium': {
        factory: () => <RemoteMessagingFramework message={rmfDataExamples.medium.content} dismiss={noop('rmf_dismiss')} />,
    },
    'rmf.big-single-action': {
        factory: () => (
            <RemoteMessagingFramework
                message={rmfDataExamples.big_single_action.content}
                primaryAction={noop('rmf_primaryAction')}
                dismiss={noop('rmf_dismiss')}
            />
        ),
    },
    'rmf.big-two-action': {
        factory: () => (
            <RemoteMessagingFramework
                message={rmfDataExamples.big_two_action.content}
                primaryAction={noop('rmf_primaryAction')}
                secondaryAction={noop('rmf_secondaryAction')}
                dismiss={noop('rmf_dismiss')}
            />
        ),
    },
};

export const otherRMFExamples = {
    'rmf.big-two-action-overflow': {
        factory: () => (
            <RemoteMessagingFramework
                message={rmfDataExamples.big_two_action_overflow.content}
                primaryAction={noop('rmf_primaryAction')}
                secondaryAction={noop('rmf_secondaryAction')}
                dismiss={noop('rmf_dismiss')}
            />
        ),
    },
};
