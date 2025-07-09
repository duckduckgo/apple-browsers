export function getRandomID() {
    if (crypto && typeof crypto.randomUUID !== 'undefined') {
        return crypto.randomUUID();
    }
    return Math.random().toString();
}
