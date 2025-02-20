function addMediaControl() {
    let userInitiated = false;

    // Listen for user interactions that may lead to playback
    ['touchstart'].forEach(eventType => {
        document.addEventListener(eventType, () => {
            userInitiated = true;

            // Unmute all media elements when user interacts
            document.querySelectorAll('audio, video').forEach(media => {
                media.muted = false;
            });

            // Reset after a short delay to prevent indefinite allowance
            setTimeout(() => {
                userInitiated = false;
            }, 500);
        }, true);  // Capture phase to detect early
    });

    // Override play to detect and conditionally allow playback
    const originalPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function() {
        if (userInitiated) {
            // User-triggered playback is allowed, so disconnect the observer and unmute
            observer.disconnect();
            this.muted = false;  // Unmute the specific media element being played
            return originalPlay.apply(this, arguments);
        } else {
            // Block programmatic playback
            this.pause();
            return Promise.reject(new Error("Playback blocked: Not user-initiated"));
        }
    };

    // Initial pause of all media
    function pauseAndMuteAllMedia() {
        document.querySelectorAll('audio, video').forEach(media => {
            media.pause();
            media.muted = true;
        });
    }

    pauseAndMuteAllMedia();

    // Monitor DOM for newly added media elements
    const observer = new MutationObserver(mutations => {
        mutations.forEach(mutation => {
            mutation.addedNodes.forEach(node => {
                if (node.tagName === 'AUDIO' || node.tagName === 'VIDEO') {
                    if (!userInitiated) {  // Only mute if not user-initiated
                        node.pause();
                        node.muted = true;
                    }
                } else if (node.querySelectorAll) {
                    node.querySelectorAll('audio, video').forEach(media => {
                        if (!userInitiated) {  // Only mute if not user-initiated
                            media.pause();
                            media.muted = true;
                        }
                    });
                }
            });
        });
    });

    observer.observe(document.body, { childList: true, subtree: true });
}

// Call the function
addMediaControl();