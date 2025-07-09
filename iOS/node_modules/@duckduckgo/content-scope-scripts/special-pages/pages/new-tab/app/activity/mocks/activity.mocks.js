/**
 * @import { ActivityData } from "../../../types/new-tab";
 * @type {Record<string, ActivityData>}
 */
export const activityMocks = {
    empty: {
        activity: [],
    },
    onlyTopLevel: {
        activity: [
            {
                favicon: { src: 'selco-icon.png' },
                url: 'https://example.com',
                title: 'example.com',
                etldPlusOne: 'example.com',
                favorite: false,
                trackersFound: false,
                trackingStatus: {
                    trackerCompanies: [],
                    totalCount: 0,
                },
                history: [],
            },
        ],
    },
    longTitle: {
        activity: [
            {
                favicon: { src: 'selco-icon.png' },
                url: 'https://deploy-preview-1468--content-scope-scripts.netlify.app',
                title: 'deploy-preview-1468--content-scope-scripts.netlify.app',
                etldPlusOne: 'deploy-preview-1468--content-scope-scripts.netlify.app',
                favorite: false,
                trackersFound: false,
                trackingStatus: {
                    trackerCompanies: [],
                    totalCount: 0,
                },
                history: [],
            },
        ],
    },
    longEntry: {
        activity: [
            {
                favicon: { src: 'selco-icon.png' },
                url: 'https://example.app',
                title: 'example.app',
                etldPlusOne: 'example.app',
                favorite: false,
                trackersFound: false,
                trackingStatus: {
                    trackerCompanies: [],
                    totalCount: 0,
                },
                history: [
                    {
                        title: '/products/bathroom/toilets-and-bidets/wall-mounted/modern-collection/ceramic-toilet-bowl?color=white&size=standard&material=porcelain&inStock=true&freeShipping=true',
                        url: 'https://example.com/products/bathroom',
                        relativeTime: 'Just now',
                    },
                ],
            },
        ],
    },
    singleWithTrackers: {
        activity: [
            {
                favicon: { src: 'selco-icon.png' },
                url: 'https://example.com',
                title: 'example.com',
                etldPlusOne: 'example.com',
                favorite: false,
                trackersFound: true,
                trackingStatus: {
                    trackerCompanies: [{ displayName: 'Google' }, { displayName: 'Facebook' }, { displayName: 'Amazon' }],
                    totalCount: 56,
                },
                history: [],
            },
        ],
    },
    few: {
        activity: [
            {
                favicon: { src: 'selco-icon.png' },
                url: 'https://example.com',
                title: 'example.com',
                etldPlusOne: 'example.com',
                favorite: false,
                trackersFound: true,
                trackingStatus: {
                    trackerCompanies: [{ displayName: 'Google' }, { displayName: 'Facebook' }, { displayName: 'Amazon' }],
                    totalCount: 56,
                },
                history: [
                    {
                        title: '/bathrooms/toilets',
                        url: 'https://example.com/bathrooms/toilets',
                        relativeTime: 'Just now',
                    },
                    {
                        title: '/kitchen/sinks',
                        url: 'https://example.com/kitchen/sinks',
                        relativeTime: '50 mins ago',
                    },
                    {
                        title: '/gardening/tools',
                        url: 'https://example.com/gardening/tools',
                        relativeTime: '18 hrs ago',
                    },
                    {
                        title: '/lighting/fixtures',
                        url: 'https://example.com/lighting/fixtures',
                        relativeTime: '1 day ago',
                    },
                ],
            },
            {
                favicon: { src: 'youtube-icon.png' },
                url: 'https://fireproof.youtube.com',
                title: 'youtube.com',
                etldPlusOne: 'youtube.com',
                favorite: true,
                trackersFound: true,
                trackingStatus: {
                    trackerCompanies: [
                        { displayName: 'Google' },
                        { displayName: 'Facebook' },
                        { displayName: 'Amazon' },
                        { displayName: 'Twitter' },
                    ],
                    totalCount: 89,
                },
                history: [
                    {
                        title: 'Great Video on YouTube',
                        url: 'https://youtube.com/watch?v=123',
                        relativeTime: '3 days ago',
                    },
                ],
            },
            {
                favicon: { src: 'amazon-icon.png' },
                url: 'https://amazon.com',
                title: 'amazon.com',
                etldPlusOne: 'amazon.com',
                favorite: false,
                trackersFound: true,
                trackingStatus: {
                    trackerCompanies: [{ displayName: 'Adobe Analytics' }, { displayName: 'Facebook' }],
                    totalCount: 12,
                },
                history: [
                    {
                        title: 'Electronics Store',
                        url: 'https://amazon.com/electronics',
                        relativeTime: '1 day ago',
                    },
                ],
            },
            {
                favicon: { src: 'twitter-icon.png' },
                url: 'https://twitter.com',
                title: 'twitter.com',
                etldPlusOne: 'twitter.com',
                favorite: false,
                trackersFound: true,
                trackingStatus: {
                    trackerCompanies: [],
                    totalCount: 0,
                },
                history: [
                    {
                        title: 'Trending Topics',
                        url: 'https://twitter.com/explore',
                        relativeTime: '2 days ago',
                    },
                ],
            },
            {
                favicon: { src: 'linkedin-icon.png' },
                url: 'https://linkedin.com',
                title: 'app.linkedin.com',
                etldPlusOne: 'linkedin.com',
                favorite: false,
                trackersFound: false,
                trackingStatus: {
                    trackerCompanies: [],
                    totalCount: 0,
                },
                history: [
                    {
                        title: 'Profile Page',
                        url: 'https://linkedin.com/in/user-profile',
                        relativeTime: '2 hrs ago',
                    },
                ],
            },
        ],
    },
};
