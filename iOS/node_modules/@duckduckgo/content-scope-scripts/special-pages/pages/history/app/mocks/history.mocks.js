import { HistoryService } from '../history.service.js';

/**
 * @type {Record<string, import("../../types/history").HistoryQueryResponse>}
 */
export const historyMocks = {
    few: {
        info: {
            finished: true,
            query: { term: '' },
        },
        value: [
            {
                id: 'history-id-01',
                dateRelativeDay: 'Today',
                dateShort: '15 Jan 2025',
                dateTimeOfDay: '11:10',
                title: 'Electric Callboy - Hypa Hypa (OFFICIAL VIDEO) - YouTube',
                url: 'https://www.youtube.com/watch?v=75Mw8r5gW8E',
                domain: 'www.youtube.com',
                etldPlusOne: 'youtube.com',
                favicon: {
                    src: './company-icons/fake.svg',
                    maxAvailableSize: 32,
                },
            },
            {
                id: 'history-id-02',
                dateRelativeDay: 'Today',
                dateShort: '15 Jan 2025',
                dateTimeOfDay: '11:01',
                title: 'Sonos continues to clean house with departure of chief commercial officer - The Verge',
                url: 'https://www.theverge.com/2025/1/15/24344430/sonos-cco-deirdre-findlay-leaving',
                domain: 'www.theverge.com',
                etldPlusOne: 'theverge.com',
            },
            {
                id: 'history-id-03',
                dateRelativeDay: 'Yesterday',
                dateShort: '14 Jan 2025',
                dateTimeOfDay: '16:45',
                title: 'PreactJS/preact: Fast 3kB React alternative with the same API. Components & Virtual DOM. - GitHub',
                url: 'https://github.com/preactjs/preact',
                domain: 'github.com',
                etldPlusOne: 'github.com',
            },
        ],
    },
};

/**
 * Generates a sample dataset with a specified number of entries, offset, and additional settings.
 *
 * @param {Object} options Configuration options for generating sample data.
 * @param {number} options.count The number of sample entries to generate.
 * @param {number} options.offset The starting index for the generated entries.
 * @return {import("../../types/history").HistoryQueryResponse['value']} An object containing metadata (info) and an array of generated sample entries (value).
 */
export function generateSampleData({ count, offset }) {
    const domains = ['youtube.com', 'theverge.com', 'github.com', 'reddit.com', 'wikipedia.org'];
    const titles = [
        'Electric Callboy - Hypa Hypa (OFFICIAL VIDEO) - YouTube',
        'Sonos continues to clean house - The Verge',
        'PreactJS/preact: Fast 3kB React alternative - GitHub',
        'A description of the vastly underrated art of sandwich making - Reddit',
        'JavaScript - Wikipedia, the free encyclopedia',
    ];
    const urls = [
        'https://www.youtube.com/watch?v=75Mw8r5gW8E',
        'https://www.theverge.com/2025/1/15/24344430/sonos-cco-deirdre-findlay-leaving',
        'https://github.com/preactjs/preact',
        'https://www.reddit.com/r/sandwiches/comments/art',
        'https://en.wikipedia.org/wiki/JavaScript',
    ];
    const dates = ['15 Jan 2025', '14 Jan 2025', '13 Jan 2025', '12 Jan 2025', '11 Jan 2025'];

    const baseDate = new Date('2025-01-15T11:10:00'); // Base date for today
    const value = [];

    for (let i = 0; i < count; i++) {
        const id = i + offset;
        const dateOffset = Math.floor(i / domains.length); // Move back a day after cycling through all domains
        const date = new Date(baseDate);
        date.setDate(date.getDate() - dateOffset);

        // Distribute attributes deterministically
        const domainIndex = i % domains.length;

        value.push({
            id: `history-id-${String(id).padStart(2, '0')}`,
            dateRelativeDay: dateOffset === 0 ? 'Today' : dateOffset === 1 ? 'Yesterday' : `${dateOffset} days ago`,
            dateShort: dates[domainIndex],
            dateTimeOfDay: date.toTimeString().split(' ')[0].slice(0, 5), // Format: "HH:MM"
            domain: domains[domainIndex],
            title: `(index:${id}) ` + titles[domainIndex],
            url: urls[domainIndex],
            etldPlusOne: domains[domainIndex],
        });

        // Adjust time for each entry so they're not identical
        baseDate.setMinutes(baseDate.getMinutes() - 9); // Deduct time deterministically
    }

    return value;
}

/**
 * @param {import("../../types/history").HistoryQueryResponse['value']} items
 * @param {number} offset
 * @param {number} chunkSize
 * @return {import("../../types/history").HistoryQueryResponse}
 */
export function asResponse(items, offset, chunkSize = HistoryService.CHUNK_SIZE) {
    // console.log(items.slice(offset, chunkSize));
    const sliced = items.slice(offset, offset + chunkSize);
    const finished = sliced.length < chunkSize;
    return {
        value: sliced,
        info: {
            finished,
            query: { term: '' },
        },
    };
}

// console.log(generateSampleData({ count: 10, offset: 0, term: '', finished: false }));
// console.log(generateSampleData({ count: 10, offset: 10, term: '', finished: true }));
