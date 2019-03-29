import Vapor
import ExtendedError

enum EntityNotFoundError: String, Error {
    case userNotFound
    case refreshTokenNotFound
    case roleNotFound
}

extension EntityNotFoundError: TerminateError {
    var status: HTTPResponseStatus {
        return .notFound
    }

    var reason: String {
        switch self {
        case .userNotFound: return "User not exists."
        case .refreshTokenNotFound: return "Refresh token not exists."
        case .roleNotFound: return "Rolenot exists."
        }
    }

    var identifier: String {
        return "entity-not-found"
    }

    var code: String {
        return self.rawValue
    }
}
