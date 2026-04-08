import Foundation

/// Common HTTP status codes.
public enum HTTPStatusCode: Int, Sendable, Hashable {
    case ok = 200
    case created = 201
    case noContent = 204
    case badRequest = 400
    case notFound = 404
    case methodNotAllowed = 405
    case internalServerError = 500

    var reasonPhrase: String {
        switch self {
        case .ok: return "OK"
        case .created: return "Created"
        case .noContent: return "No Content"
        case .badRequest: return "Bad Request"
        case .notFound: return "Not Found"
        case .methodNotAllowed: return "Method Not Allowed"
        case .internalServerError: return "Internal Server Error"
        }
    }
}
