// ✅ CORRECT: Modern async/await with proper error handling
@MainActor
class FeatureViewModel: ObservableObject {
    @Published var state: FeatureState = .idle
    
    func loadData() async {
        state = .loading
        
        do {
            let data = try await service.fetchData()
            state = .loaded(data)
        } catch {
            state = .error(error)
        }
    }
}

