window.dispatchEvent(
    new CustomEvent('ddg-serp-yt-response', {
        detail: { 
            kind: 'initialSetup', 
            data: {
                privatePlayerMode: { enabled: {} },
                overlayInteracted: false,
            }
        },
        composed: true,
        bubbles: true,
    }),
)