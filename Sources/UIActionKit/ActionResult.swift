import Foundation

/// The result of executing a UI action.
public struct ActionResult: Codable, Sendable {
    public let success: Bool
    public let message: String
    public let duration: TimeInterval

    public init(success: Bool, message: String, duration: TimeInterval) {
        self.success = success
        self.message = message
        self.duration = duration
    }

    public static func ok(message: String = "Action completed", duration: TimeInterval = 0) -> ActionResult {
        ActionResult(success: true, message: message, duration: duration)
    }

    public static func failure(message: String, duration: TimeInterval = 0) -> ActionResult {
        ActionResult(success: false, message: message, duration: duration)
    }
}
