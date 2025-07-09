/**
 * @type {Record<string, {content: NonNullable<import("../../../types/new-tab").FreemiumPIRBannerData['content']>}>}

 */
export const freemiumPIRDataExamples = {
    onboarding: {
        content: {
            messageType: 'big_single_action',
            id: 'onboarding',
            titleText: 'Personal Information Removal',
            descriptionText: 'Find out which sites are selling **your info**.',
            actionText: 'Free Scan',
        },
    },
    scan_results: {
        content: {
            messageType: 'big_single_action',
            id: 'scan_results',
            titleText: null,
            descriptionText: 'Your free personal information scan found 19 records about you on 3 different sites',
            actionText: 'View Results',
        },
    },
};
