export function extname(url) {
    let endOfPath = url.length;
    // Check for fragment
    const indexOfFragment = url.indexOf('#');
    if (indexOfFragment !== -1) {
        endOfPath = indexOfFragment;
    }
    const indexOfQuery = url.indexOf('?');
    if (indexOfQuery !== -1 && indexOfQuery < endOfPath) {
        endOfPath = indexOfQuery;
    }
    let startOfExt = endOfPath - 1;
    let code = 0;
    for (; startOfExt >= 0; startOfExt -= 1) {
        code = url.charCodeAt(startOfExt);
        if (((code >= 65 && code <= 90) ||
            (code >= 97 && code <= 122) ||
            (code >= 48 && code <= 57)) === false) {
            break;
        }
    }
    if (code !== 46 || startOfExt < 0 || endOfPath - startOfExt >= 10) {
        return '';
    }
    return url.slice(startOfExt + 1, endOfPath);
}
//# sourceMappingURL=extname.js.map