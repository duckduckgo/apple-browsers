export const ROW_SIZE = 28;
export const TITLE_SIZE = 32;
export const END_SIZE = 24;
export const TITLE_KIND = ROW_SIZE + TITLE_SIZE;
export const END_KIND = ROW_SIZE + END_SIZE;
export const BOTH_KIND = ROW_SIZE + TITLE_SIZE + END_SIZE;

/**
 * @param {import("../types/history").HistoryItem[]} rows
 * @return {number[]}
 */
export function generateHeights(rows) {
    const heights = new Array(rows.length);
    for (let i = 0; i < rows.length; i++) {
        const curr = rows[i];
        const prev = rows[i - 1];
        const next = rows[i + 1];
        const isStart = curr.dateRelativeDay !== prev?.dateRelativeDay;
        const isEnd = curr.dateRelativeDay !== next?.dateRelativeDay;

        if (isStart && isEnd) {
            heights[i] = TITLE_SIZE + ROW_SIZE + END_SIZE;
        } else if (isStart) {
            heights[i] = TITLE_SIZE + ROW_SIZE;
        } else if (isEnd) {
            heights[i] = ROW_SIZE + END_SIZE;
        } else {
            heights[i] = ROW_SIZE;
        }
    }
    return heights;
}

/**
 * Convert the items 'id' field into something that is safe to use in
 * things CSS view transition names.
 *
 * Note: I am not checking if the generated id starts with a number,
 * because the names will always be prefixed in the component.
 *
 * @param {import("../types/history").HistoryItem[]} rows
 * @return {string[]}
 */
export function generateViewIds(rows) {
    return rows.map((row) => {
        return btoa(row.id).replace(/=/g, '');
    });
}

/**
 * @typedef {'ctrl+click' | 'shift+click' | 'click' | 'escape' | 'delete' | 'shift+up' | 'shift+down' | 'up' | 'down' | 'unknown'} Intention
 */

/**
 * @param {MouseEvent|KeyboardEvent} event
 * @param {ImportMeta['platform']} platformName
 * @return {Intention}
 */
export function eventToIntention(event, platformName) {
    if (event instanceof MouseEvent) {
        const isControlClick = platformName === 'macos' ? event.metaKey : event.ctrlKey;
        if (isControlClick) {
            return 'ctrl+click';
        } else if (event.shiftKey) {
            return 'shift+click';
        }
        return 'click';
    } else if (event instanceof KeyboardEvent) {
        if (event.key === 'Escape') {
            return 'escape';
        } else if (event.key === 'Delete' || event.key === 'Backspace') {
            return 'delete';
        } else if (event.key === 'ArrowUp' && event.shiftKey) {
            return 'shift+up';
        } else if (event.key === 'ArrowDown' && event.shiftKey) {
            return 'shift+down';
        } else if (event.key === 'ArrowUp') {
            return 'up';
        } else if (event.key === 'ArrowDown') {
            return 'down';
        }
    }
    return 'unknown';
}

/**
 * @param {any} condition
 * @param {string} [message]
 * @return {asserts condition}
 */
export function invariant(condition, message) {
    if (condition) return;
    if (message) throw new Error('Invariant failed: ' + message);
    throw new Error('Invariant failed');
}
