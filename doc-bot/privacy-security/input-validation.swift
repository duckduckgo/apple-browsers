extension String {
    var sanitizedForWeb: String {
        // Remove potentially dangerous characters
        return self.replacingOccurrences(of: "<", with: "&lt;")
                   .replacingOccurrences(of: ">", with: "&gt;")
                   .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

