(function () {
    function postMessage (payload) {
        try {
            webkit.messageHandlers.fixedElementEdgesDetected.postMessage(payload)
        } catch (error) {
            // no-op
        }
    }

    function isVisible (style, rect) {
        return rect.width > 0 &&
            rect.height > 0 &&
            style.display !== 'none' &&
            style.visibility !== 'hidden' &&
            style.opacity !== '0'
    }

    function detectFixedEdges (shouldPost = true) {
        let top = false
        let bottom = false
        var fixedElements = 0
        var visibleFixedElements = 0
        var edgeSpanningFixedElements = 0
        var backgroundPaintingFixedElements = 0
        const edgeTolerance = 1
        const minimumEdgeCoverage = 0.8
        const elements = document.querySelectorAll('*')

        for (const element of elements) {
            const style = window.getComputedStyle(element)
            if (style.position !== 'fixed') {
                continue
            }
            fixedElements += 1

            const rect = element.getBoundingClientRect()
            if (!isVisible(style, rect)) {
                continue
            }
            visibleFixedElements += 1
            if (rect.width < window.innerWidth * minimumEdgeCoverage) {
                continue
            }
            edgeSpanningFixedElements += 1
            const paintsBackground = (style.backgroundImage !== 'none' &&
                style.backgroundImage !== '') ||
                (style.backgroundColor !== 'transparent' &&
                    style.backgroundColor !== 'rgba(0, 0, 0, 0)')
            if (!paintsBackground) {
                continue
            }
            backgroundPaintingFixedElements += 1

            top = top || (rect.top <= edgeTolerance && rect.bottom > 0)
            bottom = bottom || (rect.bottom >= window.innerHeight - edgeTolerance && rect.top < window.innerHeight)
            if (top && bottom) {
                break
            }
        }

        const result = {
            stage: 'scanCompleted',
            top,
            bottom,
            elementsScanned: elements.length,
            fixedElements,
            visibleFixedElements,
            edgeSpanningFixedElements,
            backgroundPaintingFixedElements,
            viewportHeight: window.innerHeight
        }
        if (shouldPost) {
            postMessage(result)
        }
        return result
    }

    window.__ddgFixedElementEdgeDetection = { scan: detectFixedEdges }
    postMessage({ stage: 'installed' })
    if (document.readyState !== 'complete') {
        window.addEventListener('load', () => detectFixedEdges(), { once: true })
    }
})()
