/**
 * @param {MouseEvent|KeyboardEvent} event
 * @param {ImportMeta['platform']} platformName
 * @return {'new-tab' | 'new-window' | 'same-tab'}
 */
export function eventToTarget(event, platformName) {
    const isControlClick = platformName === 'macos' ? event.metaKey : event.ctrlKey;
    if (isControlClick || ('button' in event && event.button === 1) /* middle click */) {
        return 'new-tab';
    } else if (event.shiftKey) {
        return 'new-window';
    }
    return 'same-tab';
}
