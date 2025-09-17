import Foundation

public final class SmartlingAPIClient {
    private let baseURL = "https://api.smartling.com"
    private let credentials: SmartlingCredentials
    private let session: URLSession
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiryDate: Date?

    public init(credentials: SmartlingCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: - Authentication

    public func authenticate() async throws {
        var request = try jsonRequest(
            method: "POST",
            path: "/auth-api/v2/authenticate",
            body: [
                "userIdentifier": credentials.userIdentifier,
                "userSecret": credentials.userSecret
            ],
            authorize: false
        )

        let (data, response) = try await session.data(for: request)
        try handleResponseOrThrow(data: data, response: response)

        let authResponse = try JSONDecoder().decode(AuthenticationResponse.self, from: data)
        self.accessToken = authResponse.response.data.accessToken
        self.refreshToken = authResponse.response.data.refreshToken
        self.tokenExpiryDate = Date().addingTimeInterval(TimeInterval(authResponse.response.data.expiresIn))
    }

    public func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw SmartlingAPIError.noRefreshToken
        }

        var request = try jsonRequest(
            method: "POST",
            path: "/auth-api/v2/authenticate/refresh",
            body: ["refreshToken": refreshToken],
            authorize: false
        )

        let (data, response) = try await session.data(for: request)
        try handleResponseOrThrow(data: data, response: response)

        let authResponse = try JSONDecoder().decode(AuthenticationResponse.self, from: data)
        self.accessToken = authResponse.response.data.accessToken
        self.refreshToken = authResponse.response.data.refreshToken
        self.tokenExpiryDate = Date().addingTimeInterval(TimeInterval(authResponse.response.data.expiresIn))
    }

    private func ensureValidToken() async throws {
        if let expiryDate = tokenExpiryDate, Date() < expiryDate.addingTimeInterval(-30) {
            // Token is still valid (with 30 second buffer)
            return
        }

        if refreshToken != nil {
            try await refreshAccessToken()
        } else {
            try await authenticate()
        }
    }

    // MARK: - Job Management

    public func createJob(_ request: CreateJobRequest) async throws -> SmartlingJob {
        try await ensureValidToken()

        var urlRequest = try jsonRequest(method: "POST", path: "/jobs-api/v3/projects/\(credentials.projectId)/jobs", body: request)

        let (data, response) = try await session.data(for: urlRequest)
        try handleResponseOrThrow(data: data, response: response)

        let jobResponse = try JSONDecoder().decode(JobResponse.self, from: data)
        return jobResponse.response.data
    }

    public func getJob(jobId: String) async throws -> SmartlingJob {
        try await ensureValidToken()

        var request = newRequest(method: "GET", path: "/jobs-api/v3/projects/\(credentials.projectId)/jobs/\(jobId)")

        let (data, response) = try await session.data(for: request)
        try handleResponseOrThrow(data: data, response: response)

        let jobResponse = try JSONDecoder().decode(JobResponse.self, from: data)
        return jobResponse.response.data
    }

    public func getJobProgress(jobId: String) async throws -> JobProgressResponse.ProgressData {
        try await ensureValidToken()

        var request = newRequest(method: "GET", path: "/jobs-api/v3/projects/\(credentials.projectId)/jobs/\(jobId)/progress")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let progressResponse = try JSONDecoder().decode(JobProgressResponse.self, from: data)
        return progressResponse.response.data
    }

    public func authorizeJob(jobId: String, localeWorkflows: [AuthorizeJobItemRequest] = []) async throws {
        try await ensureValidToken()
        
        let request = AuthorizeJobRequest(localeWorkflows: localeWorkflows)
        let urlRequest = try jsonRequest(method: "POST", path: "/jobs-api/v3/projects/\(credentials.projectId)/jobs/\(jobId)/authorize", body: request)
        
        let (data, response) = try await session.data(for: urlRequest)
        try handleResponseOrThrow(data: data, response: response)
    }

    // MARK: - Batch Operations

    public func createBatch(request: CreateBatchRequest) async throws -> BatchResponse.BatchData {
        try await ensureValidToken()

        var urlRequest = try jsonRequest(method: "POST", path: "/job-batches-api/v2/projects/\(credentials.projectId)/batches", body: request)

        let (data, response) = try await session.data(for: urlRequest)
        try handleResponseOrThrow(data: data, response: response)

        let batchResponse = try JSONDecoder().decode(BatchResponse.self, from: data)
        return batchResponse.response.data
    }

    // MARK: - File Uploads

    public func uploadFile(
        fileData: Data,
        fileName: String,
        fileUri: String,
        fileType: String,
        authorize: Bool? = nil,
        localeIds: [String]? = nil
    ) async throws -> String {
        try await ensureValidToken()

        let url = URL(string: "\(baseURL)/files-api/v2/projects/\(credentials.projectId)/file")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // fileUri
        body.appendMultipartField(name: "fileUri", value: fileUri, boundary: boundary)
        // fileType
        body.appendMultipartField(name: "fileType", value: fileType, boundary: boundary)
        // authorize (optional)
        if let authorize = authorize {
            body.appendMultipartField(name: "authorize", value: authorize ? "true" : "false", boundary: boundary)
        }
        // localeIds[] (optional)
        if let localeIds = localeIds {
            for locale in localeIds {
                body.appendMultipartField(name: "localeIds[]", value: locale, boundary: boundary)
            }
        }
        // file
        body.appendMultipartFile(name: "file", filename: fileName, mimeType: mimeType(for: fileName, declaredType: fileType), fileData: fileData, boundary: boundary)
        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try handleResponseOrThrow(data: data, response: response)

        // Some Smartling environments respond with 204 No Content or empty JSON body on success
        if data.isEmpty {
            return fileUri
        }
        if let uploadResponse = try? JSONDecoder().decode(UploadFileResponse.self, from: data) {
            return uploadResponse.response.data.fileUri
        }
        // If body is non-empty but not in expected shape, still proceed with provided fileUri
        return fileUri
    }

    // MARK: - Job Batches V2 Uploads

    public func uploadFileToBatch(
        batchUid: String,
        fileData: Data,
        fileName: String,
        fileUri: String,
        localeIds: [String]
    ) async throws {
        try await ensureValidToken()

        let url = URL(string: "\(baseURL)/job-batches-api/v2/projects/\(credentials.projectId)/batches/\(batchUid)/file")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipartField(name: "fileUri", value: fileUri, boundary: boundary)
        body.appendMultipartField(name: "fileType", value: fileTypeForFileName(fileName), boundary: boundary)
        for loc in localeIds { body.appendMultipartField(name: "localeIdsToAuthorize[]", value: loc, boundary: boundary) }
        body.appendMultipartFile(name: "file", filename: fileName, mimeType: mimeType(for: fileName, declaredType: fileName), fileData: fileData, boundary: boundary)
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try handleResponseOrThrow(data: data, response: response)
    }

    public func getBatchStatus(batchUid: String) async throws -> BatchStatusResponse.BatchInfo {
        try await ensureValidToken()
        let url = URL(string: "\(baseURL)/job-batches-api/v2/projects/\(credentials.projectId)/batches/\(batchUid)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try handleResponseOrThrow(data: data, response: response)
        return try JSONDecoder().decode(BatchStatusResponse.self, from: data).response.data
    }

    // MARK: - File Downloads

    public func downloadTranslatedFile(fileUri: String, localeId: String) async throws -> Data {
        try await ensureValidToken()

        var components = URLComponents(string: "\(baseURL)/files-api/v2/projects/\(credentials.projectId)/locales/\(localeId)/file")!
        components.queryItems = [
            URLQueryItem(name: "fileUri", value: fileUri)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try handleResponseOrThrow(data: data, response: response)

        return data
    }

    public func downloadAllTranslatedFiles(fileUri: String) async throws -> Data {
        try await ensureValidToken()

        var components = URLComponents(string: "\(baseURL)/files-api/v2/projects/\(credentials.projectId)/locales/all/file/zip")!
        components.queryItems = [
            URLQueryItem(name: "fileUri", value: fileUri)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return data
    }

    public func downloadTranslatedFiles(forJob jobId: String) async throws -> [DownloadedFile] {
        // Get job details first to get target locales
        let _ = try await getJob(jobId: jobId)

        // This would typically need to get the file URIs from the job's batch information
        // For now, returning empty array as the exact endpoint for getting batch files isn't clear
        // In production, you'd need to:
        // 1. Get batch details for the job
        // 2. Get file URIs from the batch
        // 3. Download each file for each locale

        return []
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SmartlingAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SmartlingAPIError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    private func handleResponseOrThrow(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SmartlingAPIError.invalidResponse
        }
        if (200...299).contains(http.statusCode) { return }
        // Try to decode Smartling error payload
        if let apiError = try? JSONDecoder().decode(SmartlingError.self, from: data) {
            let message = apiError.response.errors?.first?.message
            throw SmartlingAPIError.httpError(statusCode: http.statusCode, message: message)
        }
        // Fallback: include raw body snippet for debugging
        let raw = String(data: data, encoding: .utf8)
        let snippet = raw?.prefix(500)
        let message = snippet.map { String($0) }
        throw SmartlingAPIError.httpError(statusCode: http.statusCode, message: message)
    }
}

// MARK: - Public convenience to fetch valid project locales
extension SmartlingAPIClient {
    public func fetchProjectLocales() async throws -> [String] {
        try await ensureValidToken()
        let url = URL(string: "\(baseURL)/projects-api/v2/projects/\(credentials.projectId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try handleResponseOrThrow(data: data, response: response)
        let decoded = try JSONDecoder().decode(ProjectsAPIDetailsResponse.self, from: data)
        return decoded.response.data.targetLocales.map { $0.localeId }
    }
}

public enum SmartlingAPIError: LocalizedError {
    case noRefreshToken
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token available. Please authenticate first."
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let message):
            if let message, !message.isEmpty { return "HTTP \(statusCode): \(message)" }
            return "HTTP error with status code: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// MARK: - Internal Helpers

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(name: String, filename: String, mimeType: String, fileData: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }
}

private func mimeType(for fileName: String, declaredType: String) -> String {
    let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    switch (declaredType.lowercased(), ext) {
    case ("xliff", _), (_, "xliff"): return "application/xliff+xml"
    case ("xml", _), (_, "xml"): return "application/xml"
    case ("json", _), (_, "json"): return "application/json"
    case ("stringsdict", _): return "application/xml"
    default: return "application/octet-stream"
    }
}

private func fileTypeForFileName(_ fileName: String) -> String {
    let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    switch ext {
    case "xliff", "xlf": return "xliff"
    case "stringsdict": return "stringsdict"
    case "strings": return "ios"
    default: return "auto"
    }
}

private struct UploadFileResponse: Codable {
    struct Response: Codable {
        struct DataObj: Codable { let fileUri: String }
        let code: String
        let data: DataObj
    }
    let response: Response
}

// MARK: - Request builders
private extension SmartlingAPIClient {
    func newRequest(method: String, path: String) -> URLRequest {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        return request
    }

    func jsonRequest<T: Encodable>(method: String, path: String, body: T, authorize: Bool = true) throws -> URLRequest {
        var request = authorize ? newRequest(method: method, path: path) : URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorize {
            request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}