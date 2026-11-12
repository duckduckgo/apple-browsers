//
//  DuckAIChatScroller.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// Duck.ai scrolls its conversation in an inner element, not the page. Native code that needs that element
/// finds it here, so there is one guess at the page's layout.
enum DuckAIChatScroller {

    /// The conversation's scrolling element, or null: the outermost vertical scroller that is most of the viewport
    /// tall and starts near its top. Cached on the page while it still fits.
    static let expression = """
    (() => {
        const fits = element => {
            const overflow = getComputedStyle(element).overflowY;
            if (overflow !== 'auto' && overflow !== 'scroll') return false;
            const rect = element.getBoundingClientRect();
            return rect.height >= innerHeight * 0.65 && rect.top <= innerHeight * 0.25;
        };
        const cache = window.__ddgDuckAIChatScroller ??= {};
        if (cache.element?.isConnected && fits(cache.element)) return cache.element;
        let best = null;
        for (const element of document.querySelectorAll('div')) {
            if (best?.contains(element) || !fits(element)) continue;
            if (!best || element.clientHeight > best.clientHeight) best = element;
        }
        cache.element = best;
        return best;
    })()
    """

    /// Whether the end of the conversation is in view above the bottom inset. One too short to scroll is; no
    /// conversation is not. A scroll that stops short counts while the inset spacer's spare room still shows.
    static let isAtBottomExpression = """
    (() => {
        const chat = \(expression);
        if (!chat) return false;
        const insets = window.__ddgNativeScrollInsets;
        const spacer = insets?.spacer?.parentElement === chat ? insets.spacer.getBoundingClientRect().height : 0;
        const slack = Math.max(4, spacer - (insets?.bottom ?? 0));
        return chat.scrollTop + chat.clientHeight >= chat.scrollHeight - slack;
    })()
    """
}
