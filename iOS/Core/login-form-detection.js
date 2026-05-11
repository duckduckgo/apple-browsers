
(function () {
    function loginFormDetected () {
        try {
            webkit.messageHandlers.loginFormDetected.postMessage({})
        } catch (error) {
            // webkit might not be defined
        }
    }

    function inputVisible (input) {
        return !(input.offsetWidth === 0 && input.offsetHeight === 0) && !input.ariaHidden && !input.hidden
    }

    function checkIsLoginForm (form) {
        const inputs = form.getElementsByTagName('input')
        if (!inputs) {
            return
        }

        for (let i = 0; i < inputs.length; i++) {
            const input = inputs.item(i)
            if (input.type === 'password' && inputVisible(input)) {
                loginFormDetected()
                return true
            }
        }

        return false
    }

    function submitHandler (event) {
        checkIsLoginForm(event.target)
    }

    function scanForForms () {
        const forms = document.forms
        if (!forms || forms.length === 0) {
            return
        }

        for (let i = 0; i < forms.length; i++) {
            const form = forms[i]
            form.removeEventListener('submit', submitHandler)
            form.addEventListener('submit', submitHandler)
        }
    }

    // *** Add listeners

    window.addEventListener('DOMContentLoaded', function (event) {
    // Wait before adding submit handlers because sometimes forms are created by JS after the DOM has loaded
        setTimeout(scanForForms, 1000)
    })

    window.addEventListener('click', scanForForms)
    window.addEventListener('beforeunload', scanForForms)

    window.addEventListener('submit', submitHandler)

    try {
        const observer = new PerformanceObserver((list, observer) => {
            const entries = list.getEntries().filter((entry) => {
                return entry.initiatorType === 'xmlhttprequest' && entry.name.split('?')[0].match(/login|sign-in/)
            })

            if (entries.length === 0) {
                return
            }

            const forms = document.forms
            if (!forms || forms.length === 0) {
                return
            }

            for (let i = 0; i < forms.length; i++) {
                if (checkIsLoginForm(forms[i])) {
                    break
                }
            }
        })
        observer.observe({ entryTypes: ['resource'] })
    } catch (error) {
        // no-op
    }
})()
