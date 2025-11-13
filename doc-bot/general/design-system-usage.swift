// ✅ REQUIRED - Use DesignResourcesKit
Text("Title")
    .foregroundColor(Color(designSystemColor: .textPrimary))

Image(uiImage: DesignSystemImages.Color.Size24.bookmark)

// ❌ FORBIDDEN - Hardcoded colors/icons
Text("Title").foregroundColor(.black)
Image(systemName: "bookmark")

