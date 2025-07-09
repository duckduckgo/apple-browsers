import ContentFeature from '../content-feature';

export default class Referrer extends ContentFeature {
    init() {
        // If the referer is a different host to the current one, trim it.
        if (document.referrer && new URL(document.URL).hostname !== new URL(document.referrer).hostname) {
            // trim referrer to origin.
            const trimmedReferer = new URL(document.referrer).origin + '/';
            this.wrapProperty(Document.prototype, 'referrer', {
                get: () => trimmedReferer,
            });
        }
    }
}
