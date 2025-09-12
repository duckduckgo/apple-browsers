---
alwaysApply: false
title: "Design System Implementation Examples"
description: "Detailed examples for DesignResourcesKit implementation in DuckDuckGo browser"
keywords: ["design system", "DesignResourcesKit", "DRK", "examples", "SwiftUI", "colors", "typography", "icons"]
---

# Design System Implementation Examples

## Color Usage Examples

```swift
// ✅ CORRECT - Use design system colors
Text("Welcome")
    .foregroundColor(Color(designSystemColor: .textPrimary))
    .background(Color(designSystemColor: .backgroundSecondary))

Button("Action") { }
    .foregroundColor(Color(designSystemColor: .textInverted))
    .background(Color(designSystemColor: .interactivePrimary))

// ❌ INCORRECT - Hardcoded colors
Text("Welcome")
    .foregroundColor(.black)
    .background(.gray)
```

## Typography Examples

```swift
// ✅ CORRECT - Use design system fonts
VStack(alignment: .leading, spacing: 8) {
    Text("Title")
        .font(Font(designSystemFont: .title1))
    
    Text("Body content here")
        .font(Font(designSystemFont: .body))
    
    Text("Caption text")
        .font(Font(designSystemFont: .caption1))
}

// ❌ INCORRECT - System fonts
Text("Title")
    .font(.system(size: 28, weight: .bold))
```

## Icon Usage Examples

```swift
// ✅ CORRECT - Use DesignResourcesKit icons
HStack {
    Image(uiImage: DesignSystemImages.Glyphs.Size16.add)
        .renderingMode(.template)
        .foregroundColor(Color(designSystemColor: .iconPrimary))
    
    Text("Add Bookmark")
}

// Different sizes available
Image(uiImage: DesignSystemImages.Glyphs.Size24.bookmark)
Image(uiImage: DesignSystemImages.Glyphs.Size20.share)
Image(uiImage: DesignSystemImages.Glyphs.Size32.shield)

// ❌ INCORRECT - System images
Image(systemName: "plus")
    .foregroundColor(.blue)
```

## Component Pattern Examples

```swift
// ✅ CORRECT - Design system button
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Font(designSystemFont: .button))
                .foregroundColor(Color(designSystemColor: .textInverted))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(Color(designSystemColor: .interactivePrimary))
        .cornerRadius(8)
    }
}

// ✅ CORRECT - Settings row component  
struct SettingsRow: View {
    let icon: UIImage
    let title: String
    let value: String?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .foregroundColor(Color(designSystemColor: .iconSecondary))
                .frame(width: 24, height: 24)
            
            Text(title)
                .font(Font(designSystemFont: .body))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            
            Spacer()
            
            if let value = value {
                Text(value)
                    .font(Font(designSystemFont: .caption1))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}
```

## Layout and Spacing Examples

```swift
// ✅ CORRECT - Use design system spacing
VStack(spacing: 16) {  // Standard spacing
    HeaderView()
    
    VStack(spacing: 8) {  // Tight spacing
        TitleView()
        SubtitleView()
    }
    .padding(20)  // Standard padding
    
    FooterView()
}
```

## Form Component Examples  

```swift
// ✅ CORRECT - Design system text field
struct DRKTextField: View {
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        TextField(placeholder, text: $text)
            .font(Font(designSystemFont: .body))
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .padding(12)
            .background(Color(designSystemColor: .backgroundSecondary))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(designSystemColor: .borderPrimary), lineWidth: 1)
            )
    }
}

// ✅ CORRECT - Design system toggle
struct DRKToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(title, isOn: $isOn)
            .font(Font(designSystemFont: .body))
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .tint(Color(designSystemColor: .interactivePrimary))
    }
}
```

## Complete View Examples

```swift
// ✅ CORRECT - Fully compliant settings view
struct BookmarkSettingsView: View {
    @State private var showFavicons = true
    @State private var sortOrder = BookmarkSortOrder.title
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    DRKToggle(
                        title: "Show Favicons",
                        isOn: $showFavicons
                    )
                    
                    Picker("Sort Order", selection: $sortOrder) {
                        ForEach(BookmarkSortOrder.allCases) { order in
                            Text(order.displayName)
                                .font(Font(designSystemFont: .body))
                                .tag(order)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            .navigationTitle("Bookmark Settings")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(designSystemColor: .backgroundPrimary))
        }
    }
}

// ✅ CORRECT - Bookmark list item
struct BookmarkRowView: View {
    let bookmark: Bookmark
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Favicon or default icon
            AsyncImage(url: bookmark.faviconURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.bookmark)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconSecondary))
            }
            .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title)
                    .font(Font(designSystemFont: .body))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .lineLimit(1)
                
                Text(bookmark.url.host ?? bookmark.url.absoluteString)
                    .font(Font(designSystemFont: .caption1))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive, action: onDelete)
        }
        .listRowBackground(Color(designSystemColor: .backgroundPrimary))
    }
}
```

## Dark Mode Adaptation Examples

```swift
// ✅ Design system colors automatically adapt to dark mode
struct AdaptiveView: View {
    var body: some View {
        VStack {
            Text("This text adapts automatically")
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .background(Color(designSystemColor: .backgroundPrimary))
            
            // No manual dark mode checking needed!
        }
    }
}

// ❌ INCORRECT - Manual dark mode handling
struct ManualDarkModeView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Text("Manual handling")
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .background(colorScheme == .dark ? .black : .white)
    }
}
```