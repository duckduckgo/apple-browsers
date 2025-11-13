// ✅ CORRECT: Use DRK view modifiers
struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Main Title")
                .daxTitle1()
                .foregroundColor(Color(designSystemColor: .textPrimary))
            
            Text("Secondary heading")
                .daxTitle3()
                .foregroundColor(Color(designSystemColor: .textPrimary))
            
            Text("Body content that automatically supports dynamic type and accessibility features.")
                .daxBody()
                .foregroundColor(Color(designSystemColor: .textSecondary))
            
            Text("Small caption text")
                .daxCaption()
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
        .padding()
    }
}

// ❌ INCORRECT: Don't use .font() modifier
Text("Title")
    .font(.title2) // This makes it harder to spot design system violations

Text("Body")
    .font(Font(UIFont.daxBody())) // Don't access UIFont directly

