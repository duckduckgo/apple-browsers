/**
 * @typedef {import("./iframe").IframeFeature} IframeFeature
 */

/**
 * @implements IframeFeature
 */
export class PIP {
    /**
     * @param {HTMLIFrameElement} iframe
     */
    iframeDidLoad(iframe) {
        try {
            const iframeDocument = iframe.contentDocument;
            const iframeWindow = iframe.contentWindow;
            if (iframeDocument && iframeWindow) {
                const CSSStyleSheet = /** @type {any} */ (iframeWindow).CSSStyleSheet;
                const styleSheet = new CSSStyleSheet();
                styleSheet.replaceSync('button.ytp-pip-button { display: inline-block !important; }');
                // See https://developer.mozilla.org/en-US/docs/Web/API/Document/adoptedStyleSheets#append_a_new_stylesheet
                iframeDocument.adoptedStyleSheets = [...iframeDocument.adoptedStyleSheets, styleSheet];
            }
        } catch (e) {
            // ignore errors
            console.warn(e);
        }

        return null;
    }
}
