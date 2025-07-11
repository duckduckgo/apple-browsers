---
alwaysApply: false
title: "SwiftUI Style Guide with Design System Integration"
description: "SwiftUI coding style and design system integration for DuckDuckGo browser including mandatory DesignResourcesKit usage"
keywords: ["SwiftUI", "design system", "DesignResourcesKit", "colors", "icons", "typography", "accessibility", "performance"]
---

# SwiftUI Style Guide with Design System Integration for DuckDuckGo Browser

## View Structure

### View Organization
```swift
struct FeatureView: View {
    // MARK: - Environment and State
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appSettings: AppSettings
    
    // MARK: - State and Binding
    @State private var localState = false
    @Binding var externalState: Bool
    
    // MARK: - View Model
    @StateObject private var viewModel: FeatureViewModel
    
    // MARK: - Body
    var body: some View {
        content
            .onAppear { viewModel.onAppear() }
    }
    
    // MARK: - Subviews
    @ViewBuilder
    private var content: some View {
        // Main content here
    }
}
```

## Design System Integration

### REQUIRED: Use DesignResourcesKit Colors
ALWAYS use semantic colors from DesignResourcesKit instead of hardcoded or system colors:

```swift
// ✅ CORRECT - DesignResourcesKit semantic colors
Text("Title")
    .foregroundColor(Color(designSystemColor: .textPrimary))
    .background(Color(designSystemColor: .surface))

VStack {
    Rectangle()
        .fill(Color(designSystemColor: .accent))
    
    Button("Action") { }
        .foregroundColor(Color(designSystemColor: .controlsFillPrimary))
}
.background(Color(designSystemColor: .background))

// ❌ INCORRECT - Hardcoded or system colors
Text("Title")
    .foregroundColor(.black) // Don't use hardcoded colors
    .background(.gray) // Don't use system colors

// ❌ INCORRECT - Manual dark mode handling
@Environment(\.colorScheme) var colorScheme
let textColor = colorScheme == .dark ? Color.white : Color.black // Use semantic colors instead
```

### REQUIRED: Use DesignResourcesKit Icons
ALWAYS use icons from DesignResourcesKitIcons package:

```swift
// ✅ CORRECT - DesignResourcesKit icons
Button(action: addAction) {
    Image(uiImage: DesignSystemImages.Glyphs.Size16.add)
        .foregroundColor(Color(designSystemColor: .accent))
}

Image(uiImage: DesignSystemImages.Color.Size24.bookmark)
    .resizable()
    .frame(width: 24, height: 24)

// ❌ INCORRECT - System or custom icons
Button(action: addAction) {
    Image(systemName: "plus") // Use DesignResourcesKit icons
}

Image("custom_icon") // Use DesignResourcesKit icons instead
```

### Design System Color Categories
Use appropriate semantic color categories:

```swift
// Text colors
.foregroundColor(Color(designSystemColor: .textPrimary))
.foregroundColor(Color(designSystemColor: .textSecondary))
.foregroundColor(Color(designSystemColor: .textLink))

// Background colors
.background(Color(designSystemColor: .background))
.background(Color(designSystemColor: .surface))
.background(Color(designSystemColor: .panel))

// Control colors
.foregroundColor(Color(designSystemColor: .controlsFillPrimary))
.foregroundColor(Color(designSystemColor: .controlsFillSecondary))

// Button colors (use specific button color tokens)
.foregroundColor(Color(designSystemColor: .buttonPrimaryText))
.background(Color(designSystemColor: .buttonPrimaryBackground))
```

### Typography with Design System
Use semantic typography that integrates with the design system:

```swift
// ✅ CORRECT - Design system typography
Text("Header")
    .font(.title2.weight(.semibold))
    .foregroundColor(Color(designSystemColor: .textPrimary))

Text("Body")
    .font(.body)
    .foregroundColor(Color(designSystemColor: .textSecondary))

Text("Caption")
    .font(.caption)
    .foregroundColor(Color(designSystemColor: .textSecondary))

// Platform-specific typography (macOS)
#if os(macOS)
Text("Preference Title")
    .font(Fonts.preferencePaneTitle)
    .foregroundColor(Color(designSystemColor: .textPrimary))
#endif
```

### Theme Integration
Use Theme protocol for complex scenarios:

```swift
// ✅ CORRECT - Theme integration for advanced scenarios
struct ComplexView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack {
            Text("Content")
                .foregroundColor(Color(themeManager.currentTheme.textColor))
        }
        .background(Color(themeManager.currentTheme.backgroundColor))
    }
}

// ✅ PREFERRED - Direct semantic colors for simple cases
struct SimpleView: View {
    var body: some View {
        Text("Content")
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .background(Color(designSystemColor: .background))
    }
}
```

## Component Patterns

### Reusable Components
- Create small, focused components
- Use ViewModifiers for common styling
- Leverage ViewBuilder for conditional content

```swift
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundColor(.white)
                .padding()
                .background(Color.accentColor)
                .cornerRadius(8)
        }
    }
}
```

### Lists and Navigation
```swift
List {
    Section {
        ForEach(items) { item in
            NavigationLink(destination: DetailView(item: item)) {
                ItemRow(item: item)
            }
        }
    } header: {
        Text("Section Title")
    }
}
.listStyle(.insetGrouped)
```

## State Management

### View Model Pattern
```swift
class FeatureViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            items = try await service.fetchItems()
        } catch {
            self.error = error
        }
    }
}
```

### Async Operations
```swift
struct ContentView: View {
    @StateObject private var viewModel = ViewModel()
    
    var body: some View {
        content
            .task {
                await viewModel.loadData()
            }
            .refreshable {
                await viewModel.refresh()
            }
    }
}
```

## Animations and Transitions

### Smooth Animations
```swift
@State private var isExpanded = false

var body: some View {
    VStack {
        content
            .frame(height: isExpanded ? 200 : 100)
            .animation(.spring(), value: isExpanded)
    }
}
```

### Custom Transitions
```swift
.transition(.asymmetric(
    insertion: .move(edge: .trailing).combined(with: .opacity),
    removal: .move(edge: .leading).combined(with: .opacity)
))
```

## Accessibility

### Always Include Accessibility
```swift
Image(systemName: "star.fill")
    .accessibilityLabel("Favorite")
    .accessibilityHint("Double tap to toggle favorite status")

Button(action: action) {
    Text("Submit")
}
.accessibilityIdentifier("submit_button")
```

## Performance Considerations

### Lazy Loading
```swift
ScrollView {
    LazyVStack {
        ForEach(items) { item in
            ItemView(item: item)
        }
    }
}
```

### Avoid Expensive Operations in Body
```swift
// Bad
var body: some View {
    let processedData = expensiveOperation(data) // Don't do this
    Text(processedData)
}

// Good
@State private var processedData: String = ""

var body: some View {
    Text(processedData)
        .onAppear {
            processedData = expensiveOperation(data)
        }
}
```

## Preview Support

### Comprehensive Previews
```swift
struct FeatureView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FeatureView()
                .previewDisplayName("Default")
            
            FeatureView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
            
            FeatureView()
                .previewDevice("iPhone SE (3rd generation)")
                .previewDisplayName("Small Device")
        }
    }
}
```