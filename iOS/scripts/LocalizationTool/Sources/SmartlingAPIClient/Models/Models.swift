import Foundation

public struct SmartlingCredentials {
    public let userIdentifier: String
    public let userSecret: String
    public let projectId: String

    public init(userIdentifier: String, userSecret: String, projectId: String) {
        self.userIdentifier = userIdentifier
        self.userSecret = userSecret
        self.projectId = projectId
    }
}

public struct AuthenticationResponse: Codable {
    public let response: ResponseData

    public struct ResponseData: Codable {
        public let code: String
        public let data: TokenData
    }

    public struct TokenData: Codable {
        public let accessToken: String
        public let expiresIn: Int
        public let refreshExpiresIn: Int
        public let refreshToken: String
        public let tokenType: String
    }
}

public struct SmartlingJob: Codable {
    public let jobId: String
    public let jobName: String
    public let jobStatus: String
    public let createdDate: String?
    public let modifiedDate: String?
    public let description: String?
    public let targetLocaleIds: [String]

    enum CodingKeys: String, CodingKey {
        case jobId = "translationJobUid"
        case jobName
        case jobStatus
        case createdDate
        case modifiedDate
        case description
        case targetLocaleIds
    }
}

public struct CreateJobRequest: Codable {
    public let jobName: String
    public let targetLocaleIds: [String]
    public let description: String?
    public let callbackUrl: String?
    public let callbackMethod: String?
    public let referenceNumber: String?

    public init(
        jobName: String,
        targetLocaleIds: [String],
        description: String? = nil,
        callbackUrl: String? = nil,
        callbackMethod: String? = nil,
        referenceNumber: String? = nil
    ) {
        self.jobName = jobName
        self.targetLocaleIds = targetLocaleIds
        self.description = description
        self.callbackUrl = callbackUrl
        self.callbackMethod = callbackMethod
        self.referenceNumber = referenceNumber
    }
}

public struct JobResponse: Codable {
    public let response: ResponseData

    public struct ResponseData: Codable {
        public let code: String
        public let data: SmartlingJob
    }
}

// MARK: - Job Authorization

public struct AuthorizeJobRequest: Codable {
    public let localeWorkflows: [AuthorizeJobItemRequest]
    
    public init(localeWorkflows: [AuthorizeJobItemRequest] = []) {
        self.localeWorkflows = localeWorkflows
    }
}

public struct AuthorizeJobItemRequest: Codable {
    public let targetLocaleId: String
    public let workflowUid: String
    
    public init(targetLocaleId: String, workflowUid: String) {
        self.targetLocaleId = targetLocaleId
        self.workflowUid = workflowUid
    }
}

public struct JobProgressResponse: Codable {
    public let response: ResponseData

    public struct ResponseData: Codable {
        public let code: String
        public let data: ProgressData
    }

    public struct ProgressData: Codable {
        public let progress: Progress
        public let targetLocales: [LocaleProgress]?
    }

    public struct Progress: Codable {
        public let percentComplete: Int
        public let wordCount: Int
        public let contentState: ContentState
    }

    public struct ContentState: Codable {
        public let inTranslation: Int?
        public let completed: Int?
        public let excluded: Int?
    }

    public struct LocaleProgress: Codable {
        public let localeId: String
        public let localeDescription: String?
        public let percentComplete: Int
        public let wordCount: Int?
    }
}

public struct CreateBatchRequest: Codable {
    public let authorize: Bool
    public let translationJobUid: String
    public let fileUris: [String]
    public let localeWorkflow: [String: String]?

    public init(
        authorize: Bool = false,
        translationJobUid: String,
        fileUris: [String],
        localeWorkflow: [String: String]? = nil
    ) {
        self.authorize = authorize
        self.translationJobUid = translationJobUid
        self.fileUris = fileUris
        self.localeWorkflow = localeWorkflow
    }
}

public struct BatchResponse: Codable {
    public let response: ResponseData

    public struct ResponseData: Codable {
        public let code: String
        public let data: BatchData
    }

    public struct BatchData: Codable {
        public let batchUid: String
    }
}

// MARK: - Job Batches V2 Status

public struct BatchStatusResponse: Codable {
    public let response: Response

    public struct Response: Codable {
        public let code: String
        public let data: BatchInfo
    }

    public struct BatchInfo: Codable {
        public let batchUid: String
        public let status: String
        public let files: [FileInfo]?
    }

    public struct FileInfo: Codable {
        public let fileUri: String?
        public let status: String?
        public let errorMessage: String?
    }
}

public struct DownloadedFile {
    public let locale: String
    public let fileUri: String
    public let content: Data
}

public struct SmartlingError: LocalizedError, Codable {
    public let response: ErrorResponse

    public struct ErrorResponse: Codable {
        public let code: String
        public let errors: [ErrorDetail]?
    }

    public struct ErrorDetail: Codable {
        public let message: String
        public let details: [String: String]?
    }

    public var errorDescription: String? {
        response.errors?.first?.message ?? "Unknown Smartling API error"
    }
}

// MARK: - Project Details (for locales)

public struct ProjectDetailsResponse: Codable {
    public let response: Response

    public struct Response: Codable {
        public let code: String
        public let data: DataObj
    }

    public struct DataObj: Codable {
        public let project: Project
    }

    public struct Project: Codable {
        public let targetLocales: [TargetLocale]
    }

    public struct TargetLocale: Codable {
        public let localeId: String
        public let description: String?
        public let enabled: Bool?
    }
}

// Some deployments of the Projects API return targetLocales at response.data.targetLocales
public struct ProjectsAPIDetailsResponse: Codable {
    public let response: Response

    public struct Response: Codable {
        public let code: String
        public let data: DataObj
    }

    public struct DataObj: Codable {
        public let targetLocales: [TargetLocale]
    }

    public struct TargetLocale: Codable {
        public let localeId: String
        public let description: String?
        public let enabled: Bool?
    }
}