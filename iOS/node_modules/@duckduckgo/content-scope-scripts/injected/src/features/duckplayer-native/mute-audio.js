// eslint-disable-next-line @typescript-eslint/ban-ts-comment
// @ts-nocheck - Typing will be fixed in the future

export function muteAudio(mute) {
    document.querySelectorAll('audio, video').forEach((media) => {
        media.muted = mute;
    });
}
