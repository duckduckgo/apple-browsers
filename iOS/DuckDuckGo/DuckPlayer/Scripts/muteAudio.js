function muteAudio(mute) {
    document.querySelectorAll('audio, video').forEach(media => {
        media.muted = mute;
    });
}