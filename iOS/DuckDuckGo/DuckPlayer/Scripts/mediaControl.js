(function() {
    // Initialize state if not exists
    if (!window._mediaControlState) {
        window._mediaControlState = {
            observer: null,
            userInitiated: false,
            originalPlay: HTMLMediaElement.prototype.play,
            originalLoad: HTMLMediaElement.prototype.load,
            isPaused: false
        };
    }
    const state = window._mediaControlState;

    // Block playback handler
    const blockPlayback = function(event) {
        event.preventDefault();
        event.stopPropagation();
        return false;
    };

    // The actual media control function
    function mediaControl(pause) {
        state.isPaused = pause;
        
        if (pause) {
            // Capture play events at the earliest possible moment
            document.addEventListener('play', blockPlayback, true);
            document.addEventListener('playing', blockPlayback, true);
            
            // Block HTML5 video/audio playback methods
            HTMLMediaElement.prototype.play = function() {
                this.pause();
                return Promise.reject(new Error('Playback blocked'));
            };
            
            // Override load to ensure media starts paused
            HTMLMediaElement.prototype.load = function() {
                this.autoplay = false;
                this.pause();
                return state.originalLoad.apply(this, arguments);
            };

            // Listen for user interactions that may lead to playback
            document.addEventListener('touchstart', () => {
                state.userInitiated = true;
                
                // Remove the early blocking listeners
                document.removeEventListener('play', blockPlayback, true);
                document.removeEventListener('playing', blockPlayback, true);
                
                // Reset HTMLMediaElement.prototype.play
                HTMLMediaElement.prototype.play = state.originalPlay;

                // Unmute all media elements when user interacts
                document.querySelectorAll('audio, video').forEach(media => {
                    media.muted = false;
                });

                // Reset after a short delay
                setTimeout(() => {
                    state.userInitiated = false;
                    
                    // Re-add blocking if still in paused state
                    if (state.isPaused) {
                        document.addEventListener('play', blockPlayback, true);
                        document.addEventListener('playing', blockPlayback, true);
                        HTMLMediaElement.prototype.play = function() {
                            this.pause();
                            return Promise.reject(new Error('Playback blocked'));
                        };
                    }
                }, 500);
            }, true);

            // Initial pause of all media
            document.querySelectorAll('audio, video').forEach(media => {
                media.pause();
                media.muted = true;
                media.autoplay = false;
            });

            // Monitor DOM for newly added media elements
            if (state.observer) {
                state.observer.disconnect();
            }
            
            state.observer = new MutationObserver(mutations => {
                mutations.forEach(mutation => {
                    // Check for added nodes
                    mutation.addedNodes.forEach(node => {
                        if (node.tagName === 'VIDEO' || node.tagName === 'AUDIO') {
                            if (!state.userInitiated) {
                                node.pause();
                                node.muted = true;
                                node.autoplay = false;
                            }
                        } else if (node.querySelectorAll) {
                            node.querySelectorAll('audio, video').forEach(media => {
                                if (!state.userInitiated) {
                                    media.pause();
                                    media.muted = true;
                                    media.autoplay = false;
                                }
                            });
                        }
                    });
                });
            });

            state.observer.observe(document.documentElement || document.body, { 
                childList: true, 
                subtree: true,
                attributes: true,
                attributeFilter: ['autoplay', 'src', 'playing']
            });
        } else {
            // Restore original methods
            HTMLMediaElement.prototype.play = state.originalPlay;
            HTMLMediaElement.prototype.load = state.originalLoad;
            
            // Remove listeners
            document.removeEventListener('play', blockPlayback, true);
            document.removeEventListener('playing', blockPlayback, true);
            
            // Clean up observer
            if (state.observer) {
                state.observer.disconnect();
                state.observer = null;
            }

            // Unmute all media
            document.querySelectorAll('audio, video').forEach(media => {
                media.muted = false;
            });
        }
    }

    // Export function
    window.mediaControl = mediaControl;
    
})();