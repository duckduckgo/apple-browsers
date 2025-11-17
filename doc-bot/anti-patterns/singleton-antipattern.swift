// ❌ AVOID - Static shared instance without DI
final class FeatureManager {
    static let shared = FeatureManager()
    private init() {}
    
    func performAction() {
        // Implementation
    }
}

// Usage:
FeatureManager.shared.performAction() // Hard to test and tightly coupled

// ✅ CORRECT - Dependency injection pattern
protocol FeatureManagerProtocol {
    func performAction()
}

final class FeatureManager: FeatureManagerProtocol {
    func performAction() {
        // Implementation
    }
}

// Register in AppDependencyProvider
extension AppDependencyProvider {
    var featureManager: FeatureManagerProtocol {
        return FeatureManager()
    }
}

// Usage:
final class ViewModel {
    private let featureManager: FeatureManagerProtocol
    
    init(dependencies: DependencyProvider = AppDependencyProvider.shared) {
        self.featureManager = dependencies.featureManager
    }
}

