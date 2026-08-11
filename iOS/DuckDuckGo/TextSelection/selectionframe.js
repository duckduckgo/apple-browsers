(function() {
    // Identifies the sending frame: WKFrameInfo has no usable identity, and comparing origins is
    // ambiguous for same-origin iframes.
    var frameToken = String(Math.random()).slice(2) + '-' + String(Math.random()).slice(2);
    var lastHasSelection = null;
    var isPending = false;

    function post(hasSelection) {
        if (hasSelection === lastHasSelection) { return; }
        lastHasSelection = hasSelection;
        try {
            window.webkit.messageHandlers.selectionFrameChanged.postMessage({
                hasSelection: hasSelection,
                frameToken: frameToken
            });
        } catch (e) {}
    }

    function hasSelection() {
        var selection = window.getSelection();
        return !!(selection && String(selection).trim().length > 0);
    }

    // A selection appearing is reported at once, so acting on it cannot outrun the message that
    // identifies its frame. Only clearing is debounced, since selectionchange also fires per caret move.
    document.addEventListener('selectionchange', function() {
        if (hasSelection()) {
            isPending = false;
            post(true);
            return;
        }
        if (isPending) { return; }
        isPending = true;
        setTimeout(function() {
            isPending = false;
            post(hasSelection());
        }, 100);
    }, true);

    // Releases the claim when the frame navigates away or is torn down. Frames that never held a
    // selection stay silent.
    window.addEventListener('pagehide', function() {
        if (lastHasSelection === true) { post(false); }
    }, true);
})();
