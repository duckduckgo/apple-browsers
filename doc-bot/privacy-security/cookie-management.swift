// Clear cookies on demand
HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeCookies], 
                                       modifiedSince: Date.distantPast)

// Implement fireproofing
let fireproofedDomains = FireproofingManager.shared.fireproofedDomains
// Preserve cookies only for fireproofed domains

