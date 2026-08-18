const expectedProfileState = typeof EXPECT_PROFILE_STATE === "undefined" ? null : EXPECT_PROFILE_STATE
const expectedInitialized = typeof EXPECT_INITIALIZED === "undefined" ? null : EXPECT_INITIALIZED === "true"
const expectedLastInitReasons = typeof EXPECT_LAST_INIT_REASON === "undefined" ? null : EXPECT_LAST_INIT_REASON.split(",")

const response = getWithRetry("http://127.0.0.1:8474/api/runtime-status", matchesExpectedStatus)

if (response.status !== 200) {
    throw new Error(`Expected /api/runtime-status 200, got ${response.status}: ${response.body}`)
}

assertExpectedStatus(JSON.parse(response.body))

function matchesExpectedStatus(body) {
    try {
        assertExpectedStatus(body)
        return true
    } catch (_) {
        return false
    }
}

function assertExpectedStatus(body) {
    if (expectedProfileState !== null && body.profileState !== expectedProfileState) {
        throw new Error(`Expected profileState=${expectedProfileState}, got ${body.profileState}`)
    }

    if (expectedInitialized !== null && body.vault.initialized !== expectedInitialized) {
        throw new Error(`Expected vault.initialized=${expectedInitialized}, got ${body.vault.initialized}`)
    }

    if (expectedLastInitReasons !== null && expectedLastInitReasons.indexOf(body.vault.lastInitReason) === -1) {
        throw new Error(`Expected vault.lastInitReason in ${expectedLastInitReasons.join(",")}, got ${body.vault.lastInitReason}`)
    }
}

function getWithRetry(url, isExpected) {
    var lastError = null

    for (var attempt = 0; attempt < 30; attempt++) {
        try {
            const response = http.get(url)
            if (response.status === 200) {
                const body = JSON.parse(response.body)
                if (isExpected(body)) {
                    return response
                }

                lastError = new Error(`Unexpected response body: ${response.body}`)
            } else {
                lastError = new Error(`Unexpected response status ${response.status}: ${response.body}`)
            }
        } catch (error) {
            lastError = error
        }

        sleep(1000)
    }

    throw lastError
}

function sleep(milliseconds) {
    const end = Date.now() + milliseconds
    while (Date.now() < end) {}
}
