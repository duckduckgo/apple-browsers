// ✅ CORRECT: Weak self pattern
resource.request().onComplete { [weak self] response in
    guard let self = self else { return }
    let model = self.updateModel(response)
    self.updateUI(model)
}

// ❌ INCORRECT: Potential crash with unowned
resource.request().onComplete { [unowned self] response in
    let model = self.updateModel(response)  // Might crash
    self.updateUI(model)
}

// ❌ INCORRECT: Optional chaining can cause issues
resource.request().onComplete { [weak self] response in
    let model = self?.updateModel(response)  // Self might be nil here
    self?.updateUI(model)                    // And here, causing inconsistency
}

