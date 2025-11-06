// ❌ AVOID - Hardcoded colors and system icons
struct FeatureView: View {
    var body: some View {
        VStack {
            Image(systemName: "star.fill") // Use DesignResourcesKit icons
                .foregroundColor(.blue)   // Use semantic colors
            
            Text("Title")
                .foregroundColor(.black)  // Doesn't adapt to dark mode
        }
        .background(.gray)               // Use semantic colors
    }
}

// ✅ CORRECT - Design system integration
struct FeatureView: View {
    var body: some View {
        VStack {
            Image(uiImage: DesignSystemImages.Color.Size16.star)
                .foregroundColor(Color(designSystemColor: .accent))
            
            Text("Title")
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
        .background(Color(designSystemColor: .surface))
    }
}

