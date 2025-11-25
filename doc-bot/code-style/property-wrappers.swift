// ✅ CORRECT: Use custom property wrappers
final class SettingsManager {
    @UserDefaultsWrapper(key: .showBookmarksBar, defaultValue: true)
    var showBookmarksBar: Bool
    
    @UserDefaultsWrapper(key: .homePageURL, defaultValue: "https://duckduckgo.com")
    var homePageURL: String
}

