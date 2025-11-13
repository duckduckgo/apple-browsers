// ✅ CORRECT pattern used throughout codebase
final class FeatureViewModel: ObservableObject {
    private let service: FeatureServiceProtocol
    
    init(dependencies: DependencyProvider = AppDependencyProvider.shared) {
        self.service = dependencies.featureService
    }
}

