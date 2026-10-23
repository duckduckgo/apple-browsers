# macOS theming

Every color in a macOS app view must follow live theme changes.

## Color lookup order

1. `theme.colorsProvider`: semantic, per-feature colors.
2. `theme.palette`: one `NSColor` per DRK token.
3. Raw DRK: `NSColor(designSystemColor:)` in AppKit, `Color(designSystemColor:palette:)` in SwiftUI.

Read `theme`, `palette` and `colorsProvider` through computed properties, never a stored `let` or `@State`.

## AppKit

Adopt `ThemeUpdateListening` and set every themed color in `applyThemeStyle(theme:)`.

```swift
let themeManager: ThemeManaging          // injected via init
var themeUpdateCancellable: AnyCancellable?

override func viewDidLoad() {
    super.viewDidLoad()
    subscribeToThemeChanges()
    applyThemeStyle()                    // initial state
}

func applyThemeStyle(theme: ThemeStyleProviding) {
    backgroundView.backgroundColor = theme.colorsProvider.bookmarksPanelBackgroundColor
}
```

A `CGColor` ignores light/dark changes: re-assign layer colors in `viewDidChangeEffectiveAppearance()` inside
`NSAppearance.withAppAppearance { }`, or use `ColorView`.

## SwiftUI

Inject the palette at a root observing `ThemeManager` and pass it as `palette:`, or the view won't re-render on a
theme switch. Existing code often omits it; new code must not.

```swift
struct RootView: View {
    @ObservedObject var themeManager: ThemeManager   // ThemeManaging isn't observable

    var body: some View {
        ChildView()
            .environment(\.designSystemPalette, themeManager.designColorPalette)
    }
}

struct ChildView: View {
    @Environment(\.designSystemPalette) private var palette

    var body: some View {
        Text("Title")
            .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
    }
}
```

A view already observing `ThemeManager` can pass `palette: themeManager.designColorPalette` directly.
