/**
 * @type {Record<string, {content: NonNullable<import("../../../types/new-tab").RMFData['content']>}>}
 */
export const rmfDataExamples = {
    small: {
        content: {
            messageType: 'small',
            id: 'id-small',
            titleText: 'Search services limited',
            descriptionText: 'Search services are impacted by a Bing outage, results may not be what you expect',
        },
    },
    medium: {
        content: {
            messageType: 'medium',
            id: 'id-2',
            icon: 'DDGAnnounce',
            titleText: 'New Search Feature!',
            descriptionText: 'DuckDuckGo now offers Instant Answers for quicker access to the information you need.',
        },
    },
    big_single_action: {
        content: {
            messageType: 'big_single_action',
            id: 'id-big-single',
            titleText: 'Tell Us Your Thoughts on Privacy Pro',
            descriptionText: 'Take our short anonymous survey and share your feedback.',
            icon: 'PrivacyPro',
            primaryActionText: 'Take Survey',
        },
    },
    big_two_action: {
        content: {
            messageType: 'big_two_action',
            id: 'id-big-two',
            titleText: 'Tell Us Your Thoughts on Privacy Pro',
            descriptionText: 'Take our short anonymous survey and share your feedback.',
            icon: 'Announce',
            primaryActionText: 'Take Survey',
            secondaryActionText: 'Remind me',
        },
    },
    big_two_action_overflow: {
        content: {
            id: 'big-two-overflow',
            messageType: 'big_two_action',
            icon: 'CriticalUpdate',
            titleText: 'Windows Update Recommended',
            descriptionText:
                'Support for Windows 10 is ending soon. Update to Windows 11 or newer before July 8, 2024, to keep getting the latest browser updates and improvements.',
            primaryActionText: 'How to update Windows',
            secondaryActionText: 'Remind me later, but only if I’m actually going to update soon',
        },
    },
};
