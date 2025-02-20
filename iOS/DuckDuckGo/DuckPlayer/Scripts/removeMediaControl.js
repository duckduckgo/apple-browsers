function removeMediaControl() {
    // Restore original play method
    if (HTMLMediaElement.prototype._originalPlay) {
        HTMLMediaElement.prototype.play = HTMLMediaElement.prototype._originalPlay;
        delete HTMLMediaElement.prototype._originalPlay;
    }
    
    // Remove event listeners (if we stored references to them)
    // Clean up any observers
    if (window._mediaObserver) {
        window._mediaObserver.disconnect();
        delete window._mediaObserver;
    }
}