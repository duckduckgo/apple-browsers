---
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
---

In the iOS app, I want to change the corner radius of our primary button style from 8 to 12. Here is the relevant part of `PrimaryButtonStyle` in the DuckUI package:

```swift
public struct PrimaryButtonStyle: ButtonStyle {
    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true) { ... }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .daxButton()
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? 40 : 50)
            .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
            .background(Color(designSystemColor: .buttonsPrimaryDefault))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

The repository is not available in this session, so work from this snippet. Do not edit any files; describe exactly what you would change and anything I should know before doing it.
