(function() {
    if (Object.prototype.hasOwnProperty.call(window, '__ddgSelectionFrame')) { return; }

    // Identifies the sending frame: WKFrameInfo has no usable identity, and comparing origins is
    // ambiguous for same-origin iframes.
    var tokenParts = new Uint32Array(4);
    crypto.getRandomValues(tokenParts);
    var frameToken = Array.from(tokenParts).join('-');
    var lastHasSelection = null;
    var clearTimer = null;
    var snapshot = '';

    // Matches isBeingFramed() in content-scope-scripts. ancestorOrigins is not forgeable from the page.
    var isFramed = (window.location && 'ancestorOrigins' in window.location)
        ? window.location.ancestorOrigins.length > 0
        : window.top !== window;

    Object.defineProperty(window, '__ddgSelectionFrame', {
        value: Object.freeze({
            // One-shot: a read happens only because the user picked an action, and the text is then spent.
            // Leaving it readable let a later sheet open re-attach a selection the user had already
            // submitted and could no longer see, since losing focus hides the selection without firing
            // selectionchange. Clearing lastHasSelection re-arms the deduplicated post(true), so the next
            // selectionchange reports again rather than the frame going silently untracked.
            readSelection: function() {
                var spent = snapshot;
                snapshot = '';
                lastHasSelection = null;
                return {
                    frameToken: frameToken,
                    selectedText: spent
                };
            }
        }),
        configurable: false,
        enumerable: false,
        writable: false
    });

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

    function selectionText() {
        var selection = window.getSelection();
        return selection ? String(selection) : '';
    }

    function cancelPendingClear() {
        if (clearTimer === null) { return; }
        clearTimeout(clearTimer);
        clearTimer = null;
    }

    // A frame the user never interacted with must not be able to claim the selection: native trusts the
    // newest claim, so an out-of-view third-party iframe could otherwise select its own text and have
    // that read in place of the user's. A subframe joins the focus chain only once focus is inside it.
    // The top frame is exempt — it is not the theft case, and gating it would rest the whole feature on
    // how hasFocus() behaves in a WKWebView.
    function canClaim() {
        return !isFramed || document.hasFocus();
    }

    // Stores the selection in this isolated world, where the page cannot reach it. This stops a later read
    // from observing text-node mutation that fires no selectionchange. It does not stop the page replacing
    // the selection: that fires selectionchange and overwrites what is stored here.
    function publish(text) {
        if (text.trim().length === 0) {
            snapshot = '';
            post(false);
            return;
        }
        // A frame that may not claim leaves its own stored selection alone rather than clearing it: text
        // selected while focus was inside this frame must stay readable if a later selectionchange arrives
        // after focus has moved out. Clearing here would drop the user's selection, not a hostile claim.
        if (!canClaim()) { return; }
        snapshot = text;
        post(true);
    }

    // A selection appearing is reported at once, so acting on it cannot outrun the message that
    // identifies its frame. Only clearing is debounced, since selectionchange also fires per caret move.
    document.addEventListener('selectionchange', function() {
        var text = selectionText();
        if (text.trim().length > 0) {
            cancelPendingClear();
            publish(text);
            return;
        }
        if (clearTimer !== null) { return; }
        clearTimer = setTimeout(function() {
            clearTimer = null;
            publish(selectionText());
        }, 100);
    }, true);

    // Releases the claim when the frame navigates away or is torn down. Frames that never held a
    // selection stay silent.
    window.addEventListener('pagehide', function() {
        cancelPendingClear();
        snapshot = '';
        if (lastHasSelection === true) { post(false); }
    }, true);

    window.addEventListener('pageshow', function(event) {
        if (!event.persisted) { return; }
        cancelPendingClear();
        lastHasSelection = null;
        publish(selectionText());
    }, true);
})();
