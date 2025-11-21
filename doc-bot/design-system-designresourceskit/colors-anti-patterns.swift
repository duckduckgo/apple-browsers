// ❌ NEVER: Hardcoded colors
view.backgroundColor = UIColor.black
text.foregroundColor = Color.blue
button.setTitleColor(UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0), for: .normal)

// ❌ NEVER: System colors for app content
view.backgroundColor = UIColor.systemBackground  // Use .background instead
label.textColor = UIColor.label                 // Use .textPrimary instead

// ❌ NEVER: Manual dark mode handling
@Environment(\.colorScheme) var colorScheme
let textColor = colorScheme == .dark ? Color.white : Color.black // Use semantic colors!

// ✅ CORRECT: Always use semantic design system colors
view.backgroundColor = UIColor(designSystemColor: .background)
label.textColor = UIColor(designSystemColor: .textPrimary)

