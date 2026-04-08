import Foundation

/// HTTP request methods as defined in RFC 7231.
public enum HTTPMethod: String, Sendable, Hashable, CaseIterable {
    case GET
    case POST
    case PUT
    case DELETE
    case PATCH
    case HEAD
    case OPTIONS

    public init?(rawValue: String) {
        switch rawValue.uppercased() {
        case "GET": self = .GET
        case "POST": self = .POST
        case "PUT": self = .PUT
        case "DELETE": self = .DELETE
        case "PATCH": self = .PATCH
        case "HEAD": self = .HEAD
        case "OPTIONS": self = .OPTIONS
        default: return nil
        }
    }
}
