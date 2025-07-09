/**
 * Converts an SVG element to a base64-encoded JPEG string.
 *
 * @param {SVGElement} svgElement - The SVG element to convert
 * @param {string} [backgroundColor='white'] - The background color for the JPEG image
 * @return {Promise<string>} - A promise that resolves to the base64-encoded JPEG image
 */
export function svgToBase64Jpg(svgElement, backgroundColor = 'white') {
    const svgString = new XMLSerializer().serializeToString(svgElement);
    const svgDataUrl = 'data:image/svg+xml;base64,' + btoa(svgString);

    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => {
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');

            if (!ctx) {
                reject(new Error('Could not get 2D context from canvas'));
                return;
            }

            canvas.width = img.width;
            canvas.height = img.height;

            ctx.fillStyle = backgroundColor;
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            ctx.drawImage(img, 0, 0);

            const jpgBase64 = canvas.toDataURL('image/jpeg');

            resolve(jpgBase64);
        };
        img.onerror = (error) => {
            reject(error);
        };

        img.src = svgDataUrl;
    });
}

/**
 * Converts an image element to a base64-encoded JPEG string
 *
 * @param {HTMLImageElement} imageElement - The image element to convert.
 * @return {string} - The base64-encoded JPEG string.
 * @throws {Error} - Throws an error if the canvas context cannot be obtained.
 */
export function imageToBase64(imageElement) {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');

    if (!ctx) {
        throw Error('[imageToBase64] Could not get 2D context from canvas');
    }

    canvas.width = imageElement.width;
    canvas.height = imageElement.height;

    ctx.drawImage(imageElement, 0, 0, canvas.width, canvas.height);

    const base64String = canvas.toDataURL('image/jpeg'); // You can change the format if needed

    return base64String;
}
