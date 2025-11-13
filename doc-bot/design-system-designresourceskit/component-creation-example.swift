// Example: Converting blue button to DRK component
public struct DRKPrimaryButton: View {
    let title: String
    let action: () -> Void
    
    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            Text(title)
                .daxBody()
                .foregroundColor(Color(designSystemColor: .buttonPrimaryText))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .background(Color(designSystemColor: .buttonPrimaryBackground))
        .cornerRadius(8)
    }
}

