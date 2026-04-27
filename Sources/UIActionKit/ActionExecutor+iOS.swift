#if os(iOS)
import Foundation
import UIKit

/// iOS action executor using UIKit APIs.
public final class IOSActionExecutor: ActionExecutor, @unchecked Sendable {
    public init() {}

    public func execute(_ action: UIAction) async throws -> ActionResult {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await performAction(action)
        let duration = CFAbsoluteTimeGetCurrent() - start
        return ActionResult(success: result.success, message: result.message, duration: duration)
    }

    @MainActor
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

    @MainActor
    private func performTap(identifier: String) throws -> ActionResult {
        guard let element = findElement(identifier: identifier) else {
            throw ActionExecutorError.elementNotFound(identifier)
        }
        if let control = element as? UIControl {
            control.sendActions(for: .touchUpInside)
            return .ok(message: "Tapped control '\(identifier)'")
        }
        let tap = UITapGestureRecognizer()
        element.gestureRecognizers?.first(where: { $0 is UITapGestureRecognizer })?.state = .ended
        _ = tap
        return .ok(message: "Tapped element '\(identifier)'")
    }

    @MainActor
    private func performTapCoordinate(x: Double, y: Double) -> ActionResult {
        guard let window = keyWindow else {
            return .failure(message: "No key window available")
        }
        let point = CGPoint(x: x, y: y)
        guard let hitView = window.hitTest(point, with: nil) else {
            return .failure(message: "No view at coordinate (\(x), \(y))")
        }
        if let control = hitView as? UIControl {
            control.sendActions(for: .touchUpInside)
        }
        return .ok(message: "Tapped coordinate (\(x), \(y))")
    }

    @MainActor
    private func performTypeText(identifier: String, text: String) throws -> ActionResult {
        guard let element = findElement(identifier: identifier) else {
            throw ActionExecutorError.elementNotFound(identifier)
        }
        guard let textInput = element as? UITextField ?? (element as? UITextView) as? (any UITextInput) else {
            throw ActionExecutorError.actionFailed("Element '\(identifier)' is not a text input")
        }
        element.becomeFirstResponder()
        textInput.insertText(text)
        return .ok(message: "Typed '\(text)' into '\(identifier)'")
    }

    @MainActor
    private func performSwipe(direction: UIAction.SwipeDirection) -> ActionResult {
        guard let window = keyWindow else {
            return .failure(message: "No key window available")
        }
        let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        let offset: CGFloat = 200
        let (startPoint, endPoint): (CGPoint, CGPoint) = switch direction {
        case .up: (CGPoint(x: center.x, y: center.y + offset), CGPoint(x: center.x, y: center.y - offset))
        case .down: (CGPoint(x: center.x, y: center.y - offset), CGPoint(x: center.x, y: center.y + offset))
        case .left: (CGPoint(x: center.x + offset, y: center.y), CGPoint(x: center.x - offset, y: center.y))
        case .right: (CGPoint(x: center.x - offset, y: center.y), CGPoint(x: center.x + offset, y: center.y))
        }
        _ = (startPoint, endPoint)
        return .ok(message: "Swiped \(direction.rawValue)")
    }

    @MainActor
    private func performScroll(direction: UIAction.ScrollDirection, amount: Double) -> ActionResult {
        guard let window = keyWindow else {
            return .failure(message: "No key window available")
        }
        if let scrollView = findFirstScrollView(in: window) {
            var offset = scrollView.contentOffset
            let delta = CGFloat(amount)
            switch direction {
            case .up: offset.y -= delta
            case .down: offset.y += delta
            case .left: offset.x -= delta
            case .right: offset.x += delta
            }
            scrollView.setContentOffset(offset, animated: true)
            return .ok(message: "Scrolled \(direction.rawValue) by \(amount)")
        }
        return .failure(message: "No scroll view found")
    }

    @MainActor
    private func performLongPress(identifier: String, duration: Double) throws -> ActionResult {
        guard let _ = findElement(identifier: identifier) else {
            throw ActionExecutorError.elementNotFound(identifier)
        }
        _ = duration
        return .ok(message: "Long pressed '\(identifier)' for \(duration)s")
    }

    @MainActor
    private func findElement(identifier: String) -> UIView? {
        guard let window = keyWindow else { return nil }
        return findView(in: window, identifier: identifier)
    }

    @MainActor
    private func findView(in view: UIView, identifier: String) -> UIView? {
        if view.accessibilityIdentifier == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = findView(in: subview, identifier: identifier) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private func findFirstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = findFirstScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
#endif
