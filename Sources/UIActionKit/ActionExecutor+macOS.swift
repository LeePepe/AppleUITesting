#if os(macOS)
import Foundation
import AppKit
import ApplicationServices

/// macOS action executor using the Accessibility (AX) API.
public final class MacOSActionExecutor: ActionExecutor, @unchecked Sendable {
    private let bundleIdentifier: String?

    public init(bundleIdentifier: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
    }

    public func execute(_ action: UIAction) async throws -> ActionResult {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try performAction(action)
        let duration = CFAbsoluteTimeGetCurrent() - start
        return ActionResult(success: result.success, message: result.message, duration: duration)
    }

    private func performAction(_ action: UIAction) throws -> ActionResult {
        switch action {
        case .tap(let identifier):
            return try performTap(identifier: identifier)
        case .tapCoordinate(let x, let y):
            return performTapCoordinate(x: x, y: y)
        case .typeText(let identifier, let text):
            return try performTypeText(identifier: identifier, text: text)
        case .swipe(let direction):
            return performSwipe(direction: direction)
        case .scroll(let direction, let amount):
            return performScroll(direction: direction, amount: amount)
        case .longPress(let identifier, let duration):
            return try performLongPress(identifier: identifier, duration: duration)
        }
    }

    private func performTap(identifier: String) throws -> ActionResult {
        let element = try findElement(identifier: identifier)
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if error != .success {
            throw ActionExecutorError.actionFailed("AXPress failed with error \(error.rawValue)")
        }
        return .ok(message: "Tapped '\(identifier)'")
    }

    private func performTapCoordinate(x: Double, y: Double) -> ActionResult {
        let point = CGPoint(x: x, y: y)
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        mouseDown?.post(tap: .cgSessionEventTap)
        mouseUp?.post(tap: .cgSessionEventTap)
        return .ok(message: "Tapped coordinate (\(x), \(y))")
    }

    private func performTypeText(identifier: String, text: String) throws -> ActionResult {
        let element = try findElement(identifier: identifier)

        let focusError = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
        if focusError != .success {
            throw ActionExecutorError.actionFailed("Could not focus element '\(identifier)'")
        }

        let setError = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        if setError != .success {
            throw ActionExecutorError.actionFailed("Could not set value on '\(identifier)'")
        }

        return .ok(message: "Typed '\(text)' into '\(identifier)'")
    }

    private func performSwipe(direction: UIAction.SwipeDirection) -> ActionResult {
        guard let screen = NSScreen.main else {
            return .failure(message: "No main screen available")
        }
        let center = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        let offset: CGFloat = 200

        let endPoint: CGPoint = switch direction {
        case .up: CGPoint(x: center.x, y: center.y - offset)
        case .down: CGPoint(x: center.x, y: center.y + offset)
        case .left: CGPoint(x: center.x - offset, y: center.y)
        case .right: CGPoint(x: center.x + offset, y: center.y)
        }

        let moveDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left)
        let moveDrag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: endPoint, mouseButton: .left)
        let moveUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: endPoint, mouseButton: .left)
        moveDown?.post(tap: .cgSessionEventTap)
        moveDrag?.post(tap: .cgSessionEventTap)
        moveUp?.post(tap: .cgSessionEventTap)
        return .ok(message: "Swiped \(direction.rawValue)")
    }

    private func performScroll(direction: UIAction.ScrollDirection, amount: Double) -> ActionResult {
        let (dx, dy): (Int32, Int32) = switch direction {
        case .up: (0, Int32(amount))
        case .down: (0, Int32(-amount))
        case .left: (Int32(amount), 0)
        case .right: (Int32(-amount), 0)
        }

        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) {
            event.post(tap: .cgSessionEventTap)
        }
        return .ok(message: "Scrolled \(direction.rawValue) by \(amount)")
    }

    private func performLongPress(identifier: String, duration: Double) throws -> ActionResult {
        let element = try findElement(identifier: identifier)

        var positionRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)

        var sizeRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        var position = CGPoint.zero
        var size = CGSize.zero
        if let posVal = positionRef {
            AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
        }
        if let sizeVal = sizeRef {
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        }

        let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left)
        mouseDown?.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: duration)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
        mouseUp?.post(tap: .cgSessionEventTap)

        return .ok(message: "Long pressed '\(identifier)' for \(duration)s")
    }

    private func findElement(identifier: String) throws -> AXUIElement {
        let appElement = try resolveAppElement()
        if let found = searchElement(appElement, identifier: identifier, depth: 0, maxDepth: 8) {
            return found
        }
        throw ActionExecutorError.elementNotFound(identifier)
    }

    private func resolveAppElement() throws -> AXUIElement {
        if let bundleId = bundleIdentifier,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            return AXUIElementCreateApplication(app.processIdentifier)
        }
        return AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
    }

    private func searchElement(_ element: AXUIElement, identifier: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        var identifierRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef)
        if let elemId = identifierRef as? String, elemId == identifier {
            return element
        }

        guard depth < maxDepth else { return nil }

        var childrenRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if let found = searchElement(child, identifier: identifier, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }
}
#endif
