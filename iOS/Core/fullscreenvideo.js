//
//  fullscreenvideo.js
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

// WKWebView doesn't define the fullscreenEnabled property, although it does support webkitEnterFullscreen.
// The workaround is to override fullscreenEnabled (if it isn't already defined), and add a custom implementation of the requestFullscreen function.
// The implementation calls through to webkitEnterFullscreen, which is defined on HTMLVideoElement.

(function () {
    const canEnterFullscreen = HTMLVideoElement.prototype.webkitEnterFullscreen !== undefined
    const browserHasExistingFullScreenSupport = document.fullscreenEnabled || document.webkitFullscreenEnabled

    // YouTube Mobile won't exit fullscreen correctly if requestFullscreen is overridden. Reference: https://github.com/brave/brave-ios/pull/2002
    const isMobile = /mobile/i.test(navigator.userAgent)
    const isIPad = /ipad/i.test(navigator.userAgent)
    const isIPhone = isMobile && !isIPad

    if (!browserHasExistingFullScreenSupport && canEnterFullscreen && !isIPhone) {
        Object.defineProperty(document, 'fullscreenEnabled', {
            value: true
        })

        // Reddit and similar sites embed the <video> inside a Web Component's shadow root,
        // which a plain querySelector won't pierce.
        const findVideo = function (root) {
            if (root instanceof HTMLVideoElement) return root
            if (root.shadowRoot) {
                const inShadow = findVideo(root.shadowRoot)
                if (inShadow) return inShadow
            }
            const direct = root.querySelector('video')
            if (direct) return direct
            const descendants = root.querySelectorAll('*')
            for (let i = 0; i < descendants.length; i++) {
                if (descendants[i].shadowRoot) {
                    const found = findVideo(descendants[i].shadowRoot)
                    if (found) return found
                }
            }
            return null
        }

        HTMLElement.prototype.requestFullscreen = function () {
            // The caller may be a sibling of the <video> (e.g. a maximize button in a custom
            // player's controls), so we walk up from `this` — crossing shadow root boundaries
            // via host — and search at each level until we find a video.
            let scope = this
            while (scope && scope !== document) {
                const video = findVideo(scope)
                if (video) {
                    video.webkitEnterFullscreen()
                    return true
                }
                scope = scope instanceof ShadowRoot ? scope.host : scope.parentNode
            }

            return false
        }
    }
})()
