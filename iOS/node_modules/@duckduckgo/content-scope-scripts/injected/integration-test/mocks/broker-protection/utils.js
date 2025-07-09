/**
 * @param {string} fileName
 */
export function getBrokerProtectionTestPageUrl(fileName) {
    return `http://localhost:3220/broker-protection/pages/${fileName}`;
}

/**
 * @param {PirState['state']} state
 * @returns {PirState}
 */
export function createPirState(state) {
    return { state };
}
