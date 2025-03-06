function getCurrentTime() {
    const video = document.querySelector('video');
    return video ? video.currentTime : 0;
}