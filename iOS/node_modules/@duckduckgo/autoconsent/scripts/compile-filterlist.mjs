import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { FiltersEngine } from '@ghostery/adblocker';

const rulesDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../rules');

const filterlistContent = fs.readFileSync(path.join(rulesDir, 'filterlist.txt'), 'utf-8');

const engine = FiltersEngine.parse(filterlistContent, {
    enableMutationObserver: false, // we don't monitor DOM changes at the moment
    loadNetworkFilters: false,
    enableHtmlFiltering: false,
    loadCSPFilters: false,
});
const serializedEngine = engine.serialize();
const properlySizedBuffer = ensure32BitAlignment(serializedEngine.buffer);
const engineJson = JSON.stringify(Array.from(new Uint32Array(properlySizedBuffer)));
const engineLength = serializedEngine.length;

/**
 * Ensures the buffer is aligned to a 32-bit boundary by padding if necessary
 * @param {Buffer} originalBuffer
 * @returns {Buffer} - The aligned buffer
 */

function ensure32BitAlignment(originalBuffer) {
    // Calculate the necessary padding for 32-bit alignment
    const padding = originalBuffer.byteLength % 4 === 0 ? 0 : 4 - (originalBuffer.byteLength % 4);

    if (padding !== 0) {
        // Create a new buffer with the required padding for 32-bit alignment
        const paddedBuffer = new ArrayBuffer(originalBuffer.byteLength + padding);

        // Create a Uint8Array view over the original and new buffers
        const originalView = new Uint8Array(originalBuffer);
        const paddedView = new Uint8Array(paddedBuffer);

        // Copy the original data into the new buffer
        paddedView.set(originalView);

        // Set the padding bytes to zero
        for (let i = originalBuffer.byteLength; i < paddedBuffer.byteLength; i++) {
            paddedView[i] = 0;
        }

        return paddedBuffer;
    }

    // If already aligned, return the original buffer
    return originalBuffer;
}

fs.writeFile(
    path.join(rulesDir, '../lib/filterlist-engine.ts'),
    `
declare global {
const BUNDLE_FILTERLIST: boolean;
}
const serializedEngine = /* @__PURE__ */ new Uint8Array(new Uint32Array(
  ${engineJson}
).buffer).slice(0, ${engineLength});
const emptyEngine = /* @__PURE__ */ new Uint8Array([]);
export default BUNDLE_FILTERLIST ? serializedEngine : emptyEngine;
`,
    () => console.log('Written filterlist-engine.ts'),
);
