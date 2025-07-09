const pizzaRelatedData = {
    phrases: [
        'pizza near me',
        'pizza delivery',
        'pizza hut',
        'pizza recipes',
        'pizza express',
        'pizza dough recipe',
        'pizza marinara',
        'pizza margherita',
        'pizzeria italiano',
        'pizza places open now',
        'pizza express menu',
        'pizza toppings',
        'pizza sauce recipe',
        'pizza napoletana',
        'pizza pasta',
    ],
    websites: ['pizzahut.com', 'dominos.com', 'papajohns.com', 'littlecaesars.com', 'pizzaexpress.com'],
    historyEntries: [
        'Best Pizza Places in New York',
        'Pizza Making Tips and Tricks',
        'Italian Pizza History',
        'Homemade Pizza Guide',
        'Pizza Dough Calculator',
    ],
};

/**
 * @param {string} term
 * @return {import("../../../types/new-tab").SuggestionsData}
 */
export function getMockSuggestions(term) {
    return {
        suggestions: {
            topHits: pizzaRelatedData.phrases
                .filter((phrase) => containsIgnoreCase(phrase, term))
                .slice(0, 3)
                .map((phrase) => ({
                    kind: /** @type {const} */ ('phrase'),
                    phrase,
                    score: random(95, 99),
                })),
            duckduckgoSuggestions: [
                ...pizzaRelatedData.websites
                    .filter((phrase) => containsIgnoreCase(phrase, term))
                    .slice(0, 2)
                    .map((website, index) => ({
                        kind: /** @type {const} */ ('bookmark'),
                        title: website,
                        url: website,
                        isFavorite: index === 0,
                        score: random(95, 99),
                    })),
                ...pizzaRelatedData.phrases
                    .filter((phrase) => containsIgnoreCase(phrase, term))
                    .slice(3, 8)
                    .map((phrase) => ({
                        kind: /** @type {const} */ ('phrase'),
                        phrase,
                    })),
                ...pizzaRelatedData.websites
                    .filter((site) => containsIgnoreCase(site, term))
                    .map((url) => ({
                        kind: /** @type {const} */ ('website'),
                        url: `https://${url}`,
                    })),
            ],
            localSuggestions: pizzaRelatedData.historyEntries
                .filter((title) => containsIgnoreCase(title, term))
                .map((title) => ({
                    kind: /** @type {const} */ ('historyEntry'),
                    title,
                    url: `https://example.com/search?q=${encodeURIComponent(title)}`,
                    score: random(80, 89),
                })),
        },
    };
}

/**
 * @param {string} text
 * @param {string} searchTerm
 * @returns {boolean}
 */
function containsIgnoreCase(text, searchTerm) {
    return text.toLowerCase().includes(searchTerm.toLowerCase());
}

/**
 * @param {number} min
 * @param {number} max
 * @returns {number}
 */
function random(min, max) {
    return min + Math.floor(Math.random() * (max - min + 1));
}
