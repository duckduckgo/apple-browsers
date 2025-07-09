/* crc32.js (C) 2014-present SheetJS -- http://sheetjs.com */
/* From: https://github.com/SheetJS/js-crc32/ */
const T = (() => {
    let c = 0;
    const table = new Int32Array(256);
    for (let n = 0; n !== 256; n += 1) {
        c = n;
        c = c & 1 ? -306674912 ^ (c >>> 1) : c >>> 1;
        c = c & 1 ? -306674912 ^ (c >>> 1) : c >>> 1;
        c = c & 1 ? -306674912 ^ (c >>> 1) : c >>> 1;
        c = c & 1 ? -306674912 ^ (c >>> 1) : c >>> 1;
        c = c & 1 ? -306674912 ^ (c >>> 1) : c >>> 1;
        c = c & 1 ? -306674912 ^ (c >>> 1) : c >>> 1;
        c = c & 1 ? -306674912 ^ (c >>> 1) : c >>> 1;
        c = c & 1 ? -306674912 ^ (c >>> 1) : c >>> 1;
        table[n] = c;
    }
    return table;
})();
export default function crc32(buf, start, end) {
    let C = 0 ^ -1;
    const L = end - 7;
    let i = start;
    while (i < L) {
        C = (C >>> 8) ^ T[(C ^ buf[i++]) & 0xff];
        C = (C >>> 8) ^ T[(C ^ buf[i++]) & 0xff];
        C = (C >>> 8) ^ T[(C ^ buf[i++]) & 0xff];
        C = (C >>> 8) ^ T[(C ^ buf[i++]) & 0xff];
        C = (C >>> 8) ^ T[(C ^ buf[i++]) & 0xff];
        C = (C >>> 8) ^ T[(C ^ buf[i++]) & 0xff];
        C = (C >>> 8) ^ T[(C ^ buf[i++]) & 0xff];
        C = (C >>> 8) ^ T[(C ^ buf[i++]) & 0xff];
    }
    while (i < L + 7) {
        C = (C >>> 8) ^ T[(C ^ buf[i++]) & 0xff];
    }
    return (C ^ -1) >>> 0;
}
//# sourceMappingURL=crc32.js.map