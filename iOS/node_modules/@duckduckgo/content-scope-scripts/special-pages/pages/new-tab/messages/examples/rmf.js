/**
 * @type {import("../../types/new-tab.js").RMFData}
 */
const rmfDataSmallMsg = {
    content: {
        messageType: 'small',
        id: 'id-1',
        titleText: 'Tell Us Your Thoughts on Privacy Pro',
        descriptionText: 'Lorem Ipsum is simply dummy text of the printing and typesetting industry.',
    },
};

/**
 * @type {import("../../types/new-tab.js").RMFData}
 */
const rmfDataMediumMsg = {
    content: {
        messageType: 'medium',
        id: 'id-2',
        icon: 'DDGAnnounce',
        titleText: 'New Search Feature!',
        descriptionText: 'DuckDuckGo now offers Instant Answers for quicker access to the information you need.',
    },
};

/**
 * @type {import("../../types/new-tab.js").RMFData}
 */
const rmfDataBigSingleActionMsg = {
    content: {
        messageType: 'big_single_action',
        id: 'id-big-single',
        titleText: 'Tell Us Your Thoughts on Privacy Pro',
        descriptionText: 'Take our short anonymous survey and share your feedback.',
        icon: 'PrivacyPro',
        primaryActionText: 'Take Survey',
    },
};

/**
 * @type {import("../../types/new-tab.js").RMFData}
 */
const rmfDataBigTwoActionMsg = {
    content: {
        messageType: 'big_two_action',
        id: 'id-big-two',
        titleText: 'Tell Us Your Thoughts on Privacy Pro',
        descriptionText: 'Take our short anonymous survey and share your feedback.',
        icon: 'Announce',
        primaryActionText: 'Take Survey',
        secondaryActionText: 'Remind me',
    },
};
