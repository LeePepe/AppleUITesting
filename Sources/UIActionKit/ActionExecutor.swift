import Foundation

/// Protocol for executing UI actions on a target application.
public protocol ActionExecutor: Sendable {
    func execute(_ action: UIAction) async throws -> ActionResult
}

/// Errors that can occur during action execution.
public enum ActionExecutorError: Error, LocalizedError {
    case elementNotFound(String)
    case actionFailed(String)
    case unsupportedPlatform
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .elementNotFound(let id):
            return "Element not found: \(id)"
        case .actionFailed(let reason):
            return "Action failed: \(reason)"
        case .unsupportedPlatform:
            return "Action not supported on this platform"
        case .timeout(let detail):
            return "Action timed out: \(detail)"
        }
    }
}

/// Creates the platform-appropriate action executor.
public func createActionExecutor(bundleIdentifier: String? = nil) -> ActionExecutor {
    #if os(iOS)
    return IOSActionExecutor()
    #elseif os(macOS)
    return MacOSActionExecutor(bundleIdentifier: bundleIdentifier)
    #else
    fatalError("Unsupported platform")
    #endif
}
