import { describe, it } from 'node:test';
import { deepEqual } from 'node:assert/strict';
import { EmbedSettings } from '../app/embed-settings.js';

describe('creates embed url', () => {
    it('handles duck scheme', () => {
        const actual = EmbedSettings.fromHref('duck://player/123')?.toEmbedUrl();
        const expected = 'https://www.youtube-nocookie.com/embed/123?iv_load_policy=1&autoplay=1&rel=0&modestbranding=1&color=white';
        deepEqual(actual, expected);
    });
    it('handles duck scheme with timestamp', () => {
        const actual = EmbedSettings.fromHref('duck://player/123?t=1h2m3s')?.toEmbedUrl();
        const expected = {
            iv_load_policy: '1',
            autoplay: '1',
            rel: '0',
            modestbranding: '1',
            color: 'white',
            start: '3723',
        };
        if (!actual) throw new Error('unreachable');
        const asParams = Object.fromEntries(new URL(actual).searchParams);
        deepEqual(asParams, expected);
    });
    it('handles duck scheme with videoID param', () => {
        const actual = EmbedSettings.fromHref('duck://player?videoID=88YIfKLDdvM&t=1h2m3s')?.toEmbedUrl();
        const expected = {
            iv_load_policy: '1',
            autoplay: '1',
            rel: '0',
            modestbranding: '1',
            color: 'white',
            start: '3723',
        };
        if (!actual) throw new Error('unreachable');
        const asParams = Object.fromEntries(new URL(actual).searchParams);
        deepEqual(asParams, expected);
    });
    it('handles yt scheme', () => {
        const actual = EmbedSettings.fromHref('https://youtube-nocookie.com/embed/88YIfKLDdvM?t=1h2m3s')?.toEmbedUrl();
        const expected = {
            iv_load_policy: '1',
            autoplay: '1',
            rel: '0',
            modestbranding: '1',
            color: 'white',
            start: '3723',
        };
        if (!actual) throw new Error('unreachable');
        const asParams = Object.fromEntries(new URL(actual).searchParams);
        deepEqual(asParams, expected);
    });
    it('handles invalid timestamp', () => {
        const actual = EmbedSettings.fromHref('https://youtube-nocookie.com/embed/88YIfKLDdvM?t=abc')?.toEmbedUrl();
        const expected = {
            iv_load_policy: '1',
            autoplay: '1',
            rel: '0',
            modestbranding: '1',
            color: 'white',
        };
        if (!actual) throw new Error('unreachable');
        const asParams = Object.fromEntries(new URL(actual).searchParams);
        deepEqual(asParams, expected);
    });
    it('can be muted', () => {
        const embed = EmbedSettings.fromHref('https://youtube-nocookie.com/embed/88YIfKLDdvM?t=abc');
        const actual = embed?.withMuted(true).toEmbedUrl();
        const expected = {
            iv_load_policy: '1',
            autoplay: '1',
            rel: '0',
            modestbranding: '1',
            color: 'white',
            muted: '1',
        };
        if (!actual) throw new Error('unreachable');
        const asParams = Object.fromEntries(new URL(actual).searchParams);
        deepEqual(asParams, expected);
    });
    it('can disable autoplay', () => {
        const embed = EmbedSettings.fromHref('https://youtube-nocookie.com/embed/88YIfKLDdvM?t=abc');
        const actual = embed?.withAutoplay(false).toEmbedUrl();
        const expected = {
            iv_load_policy: '1',
            rel: '0',
            modestbranding: '1',
            color: 'white',
        };
        if (!actual) throw new Error('unreachable');
        const asParams = Object.fromEntries(new URL(actual).searchParams);
        deepEqual(asParams, expected);
    });
    it('can respects default autoplay settings (stays on when the setting is undefined)', () => {
        const embed = EmbedSettings.fromHref('https://youtube-nocookie.com/embed/88YIfKLDdvM?t=abc');
        const actual = embed?.withAutoplay(undefined).toEmbedUrl();
        const expected = {
            iv_load_policy: '1',
            autoplay: '1',
            rel: '0',
            modestbranding: '1',
            color: 'white',
        };
        if (!actual) throw new Error('unreachable');
        const asParams = Object.fromEntries(new URL(actual).searchParams);
        deepEqual(asParams, expected);
    });
});
