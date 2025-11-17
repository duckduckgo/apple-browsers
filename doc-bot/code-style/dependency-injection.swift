// ✅ CORRECT: Dependency injection pattern
final class FeatureViewModel: ObservableObject {
    private let service: FeatureServiceProtocol
    
    init(dependencies: DependencyProvider = AppDependencyProvider.shared) {
        self.service = dependencies.featureService
    }
}

