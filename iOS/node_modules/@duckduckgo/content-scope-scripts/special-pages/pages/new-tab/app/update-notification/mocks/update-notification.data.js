/**
 * @type {Record<string, {content: NonNullable<import("../../../types/new-tab").UpdateNotificationData['content']>}>}
 */
export const updateNotificationExamples = {
    empty: {
        content: {
            version: '1.65.0',
            notes: [],
        },
    },
    populated: {
        content: {
            // prettier-ignore
            notes: [
                '• Bug fixes and improvements',
                'Optimized performance for faster load times'
            ],
            version: '1.91',
        },
    },
    multipleSections: {
        content: {
            // prettier-ignore
            notes: [
                `• We're excited to introduce a new browsing feature - Fire Windows. These special windows work the same way as normal windows, except they isolate your activity from other browsing data and self-destruct when closed. This means you can use a Fire Window to browse without saving local history or to sign into a site with a different account. You can open a new Fire Window anytime from the Fire Button menu.`,
                `• Try the new bookmark management view that opens in a tab for more robust bookmark organization.`,
                `For Privacy Pro subscribers`,
                `• VPN notifications are now available to help communicate VPN status.`,
                `• Some apps aren't compatible with VPNs. You can now exclude these apps to use them while connected to the VPN.`,
                `• Visit https://duckduckgo.com/pro for more information.`,
            ],
            version: '0.98.4',
        },
    },
};
