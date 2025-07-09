export class EmbedSettings {
    /**
     * @param {object} params
     * @param {VideoId} params.videoId - videoID is required
     * @param {Timestamp|null|undefined} params.timestamp - optional timestamp
     * @param {boolean} [params.autoplay] - optional timestamp
     * @param {boolean} [params.muted] - optionally start muted
     */
    constructor({ videoId, timestamp, autoplay = true, muted = false }) {
        this.videoId = videoId;
        this.timestamp = timestamp;
        this.autoplay = autoplay;
        this.muted = muted;
    }

    /**
     * @param {boolean|null|undefined} autoplay
     * @return {EmbedSettings}
     */
    withAutoplay(autoplay) {
        if (typeof autoplay !== 'boolean') return this;
        return new EmbedSettings({
            ...this,
            autoplay,
        });
    }

    /**
     * @param {boolean|null|undefined} muted
     * @return {EmbedSettings}
     */
    withMuted(muted) {
        if (typeof muted !== 'boolean') return this;
        return new EmbedSettings({
            ...this,
            muted,
        });
    }

    /**
     * @param {string|null|undefined} href
     * @returns {EmbedSettings|null}
     */
    static fromHref(href) {
        try {
            return new EmbedSettings({
                videoId: VideoId.fromHref(href),
                timestamp: Timestamp.fromHref(href),
            });
        } catch (e) {
            console.error(e);
            return null;
        }
    }

    /**
     * @return {string}
     */
    toEmbedUrl() {
        const url = new URL(`/embed/${this.videoId.id}`, 'https://www.youtube-nocookie.com');

        url.searchParams.set('iv_load_policy', '1'); // show video annotations

        if (this.autoplay) {
            url.searchParams.set('autoplay', '1'); // autoplays the video as soon as it loads

            if (this.muted) {
                url.searchParams.set('muted', '1'); // certain platforms require this to be muted to autoplay
            }
        }

        url.searchParams.set('rel', '0'); // shows related videos from the same channel as the video
        url.searchParams.set('modestbranding', '1'); // disables showing the YouTube logo in the video control bar
        url.searchParams.set('color', 'white'); // Forces legacy YouTube player UI

        if (this.timestamp && this.timestamp.seconds > 0) {
            url.searchParams.set('start', String(this.timestamp.seconds)); // if timestamp supplied, start video at specific point
        }

        return url.href;
    }

    /**
     * @param {URL} base
     * @return {string}
     */
    intoYoutubeUrl(base) {
        const url = new URL(base);
        url.searchParams.set('v', this.videoId.id);
        if (this.timestamp && this.timestamp.seconds > 0) {
            url.searchParams.set('t', `${this.timestamp.seconds}s`);
        }
        return url.toString();
    }
}

/**
 * Represents a valid ID.
 */
class VideoId {
    /**
     * @param {string|null|undefined} input
     * @throws {Error}
     */
    constructor(input) {
        if (typeof input !== 'string') throw new Error('string required, got: ' + input);
        const sanitized = sanitizeYoutubeId(input);
        if (sanitized === null) throw new Error('invalid ID from: ' + input);
        this.id = sanitized;
    }

    /**
     * @param {string|null|undefined} href
     */
    static fromHref(href) {
        return new VideoId(idFromHref(href));
    }
}

/**
 * Represents a valid timestamp.
 */
class Timestamp {
    /**
     * @param {string|null|undefined} input
     * @throws {Error}
     */
    constructor(input) {
        if (typeof input !== 'string') throw new Error('string required for timestamp');
        const seconds = timestampInSeconds(input);
        if (seconds === null) throw new Error('invalid input for timestamp: ' + input);
        this.seconds = seconds;
    }

    /**
     * @param {string|null|undefined} href
     * @return {Timestamp|null}
     */
    static fromHref(href) {
        if (typeof href !== 'string') return null;
        const param = timestampFromHref(href);
        if (param) {
            try {
                return new Timestamp(param);
            } catch (e) {
                return null;
            }
        }
        return null;
    }
}

/**
 * @param {string|null|undefined} href
 * @return {string|null}
 */
function idFromHref(href) {
    if (typeof href !== 'string') return null;

    let url;

    try {
        url = new URL(href);
    } catch (e) {
        return null;
    }

    const fromParam = url.searchParams.get('videoID');

    if (fromParam) return fromParam;

    if (url.protocol === 'duck:') {
        return url.pathname.slice(1);
    }

    if (url.pathname.includes('/embed/')) {
        return url.pathname.replace('/embed/', '');
    }

    return null;
}

/**
 * @param {string|null|undefined} href
 * @return {string|null}
 */
function timestampFromHref(href) {
    if (typeof href !== 'string') return null;

    let url;

    try {
        url = new URL(href);
    } catch (e) {
        console.error(e);
        return null;
    }

    const timeParameter = url.searchParams.get('t');

    if (timeParameter) {
        return timeParameter;
    }

    return null;
}

/**
 * Converts a timestamp in the format "<number><optional letter>" to the number of seconds.
 *
 * @param {string} timestamp - The timestamp to convert.
 * @return {number | null} - The number of seconds in the timestamp, or null if the timestamp is invalid.
 */
function timestampInSeconds(timestamp) {
    const units = {
        h: 3600,
        m: 60,
        s: 1,
    };

    const parts = timestamp.split(/(\d+[hms]?)/);

    const totalSeconds = parts.reduce((total, part) => {
        if (!part) return total;

        for (const unit in units) {
            if (part.includes(unit)) {
                return total + parseInt(part) * units[unit];
            }
        }

        return total;
    }, 0);

    if (totalSeconds > 0) {
        return totalSeconds;
    }

    return null;
}

/**
 * Sanitizes an input string by removing characters that are not alphanumeric, hyphen, or underscore.
 *
 * @param {string} input - The input string to be sanitized.
 * @return {string|null} - The sanitized string or null if the input string contains invalid characters.
 */
function sanitizeYoutubeId(input) {
    const subject = input.slice(0, 11);
    if (/^[a-zA-Z0-9-_]+$/.test(subject)) {
        return subject;
    }
    return null;
}
