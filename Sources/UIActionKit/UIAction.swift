import Foundation

/// Represents a UI action that can be performed on an element.
public enum UIAction: Codable, Sendable {
    case tap(identifier: String)
    case tapCoordinate(x: Double, y: Double)
    case typeText(identifier: String, text: String)
    case swipe(direction: SwipeDirection)
    case scroll(direction: ScrollDirection, amount: Double)
    case longPress(identifier: String, duration: Double)

    public enum SwipeDirection: String, Codable, Sendable {
        case up, down, left, right
    }

    public enum ScrollDirection: String, Codable, Sendable {
        case up, down, left, right
    }
}
