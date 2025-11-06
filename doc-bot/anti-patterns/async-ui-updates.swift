// ❌ AVOID - UI updates without main thread guarantee
class ViewModel: ObservableObject {
    @Published var isLoading = false
    
    func loadData() async {
        isLoading = true // May crash if not on main thread
        let data = try? await service.fetchData()
        isLoading = false // May crash if not on main thread
    }
}

// ✅ CORRECT - @MainActor for UI updates
@MainActor
class ViewModel: ObservableObject {
    @Published var isLoading = false
    
    func loadData() async {
        isLoading = true
        let data = try? await service.fetchData()
        isLoading = false
    }
}

