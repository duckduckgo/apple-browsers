//
//  translation.js  (POC — extract + write-back)
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//
//  Defines window.__ddgPOC with three methods, invoked on-demand via evaluateJavaScript:
//    extract()        -> walks the page, records each innermost text-bearing BLOCK element,
//                        returns [{id, text, vp}] where `text` is the block's innerHTML.
//    apply(updates)   -> writes translated innerHTML back into the recorded blocks, matched by id.
//    revert()         -> restores each block's original innerHTML.
//  Sending a whole block's innerHTML (e.g. "<p>The <b>quick</b> fox</p>") keeps sentence context for
//  the translator and preserves inline formatting. Tag alignment can drift on heavy reordering — a
//  known, accepted trade-off for this spike. Element refs persist on `window` between calls.
//

(function () {
    'use strict';

    var SKIP_TAGS = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1, TITLE: 1, HEAD: 1 };

    // Inline-level display values: an element with one of these flows inside a line of text rather
    // than forming its own block. Everything else (block, flex, grid, list-item, table-cell, ...) is
    // treated as a block.
    var INLINE_DISPLAY = {
        'inline': 1, 'inline-block': 1, 'inline-flex': 1, 'inline-grid': 1,
        'inline-table': 1, 'contents': 1, 'ruby': 1, 'ruby-base': 1, 'ruby-text': 1
    };

    function displayOf(el) {
        var s = window.getComputedStyle(el);
        return s ? s.display : 'block';
    }

    function isVisible(el) {
        var s = window.getComputedStyle(el);
        if (!s) return true;
        return s.display !== 'none' && s.visibility !== 'hidden' && s.opacity !== '0';
    }

    // A visible block child means `el` is a container of other blocks, not a leaf text block.
    function hasBlockChild(el) {
        var kids = el.children;
        for (var i = 0; i < kids.length; i++) {
            var d = displayOf(kids[i]);
            if (d === 'none') continue;
            if (!INLINE_DISPLAY[d]) return true;
        }
        return false;
    }

    // Technical / non-content subtrees we never want inside a translation unit: they bloat the
    // fragment (inline <script> JSON, <svg> path data), and Apple mangles or translates their
    // internals. A block containing any of these is skipped so the walker descends to cleaner blocks.
    var JUNK = 'script, style, noscript, svg, iframe, template';

    // A translation unit is the INNERMOST block element that holds text: itself a block, with no
    // block children (so its content is one run of text + inline formatting), containing real letters.
    function isBlockUnit(el) {
        if (INLINE_DISPLAY[displayOf(el)]) return false;   // inline → a block ancestor owns this text
        if (hasBlockChild(el)) return false;               // container of blocks → descend instead
        if (el.querySelector(JUNK)) return false;          // contains technical junk → descend instead
        return /\p{L}/u.test(el.textContent || '');        // skip number-/symbol-/icon-only blocks
    }

    var api = {
        _els: [],
        _originals: [],

        extract: function () {
            this._els = [];
            this._originals = [];
            var out = [];
            var vh = window.innerHeight || document.documentElement.clientHeight;
            var root = document.body || document.documentElement;
            if (!root) return out;
            var walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT, {
                acceptNode: function (el) {
                    if (SKIP_TAGS[el.tagName]) return NodeFilter.FILTER_REJECT; // skip whole subtree
                    if (!isVisible(el)) return NodeFilter.FILTER_REJECT;        // skip hidden subtree
                    return NodeFilter.FILTER_ACCEPT;
                }
            });
            var el;
            while ((el = walker.nextNode())) {
                if (!isBlockUnit(el)) continue;
                var html = (el.innerHTML || '').trim();
                if (!html) continue;
                var rect = el.getBoundingClientRect();
                var vp = (rect.bottom > 0 && rect.top < vh) ? 1 : 0;
                var id = this._els.length;
                this._els.push(el);
                this._originals.push(el.innerHTML);
                out.push({ id: id, text: html, vp: vp });
            }
            return out;
        },

        apply: function (updates) {
            if (typeof updates === 'string') { updates = JSON.parse(updates); }
            var count = 0;
            for (var i = 0; i < updates.length; i++) {
                var el = this._els[updates[i].id];
                if (el) { el.innerHTML = updates[i].text; count++; }
            }
            return count;
        },

        revert: function () {
            var count = 0;
            for (var i = 0; i < this._els.length; i++) {
                if (this._els[i] && this._originals[i] != null) {
                    this._els[i].innerHTML = this._originals[i];
                    count++;
                }
            }
            return count;
        }
    };

    window.__ddgPOC = api;
    return true;
})();
