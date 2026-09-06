import Combine
import SwiftUI
import UIKit

enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    static var overlapPublisher: AnyPublisher<CGFloat, Never> {
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .compactMap(overlap(from:))
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }
        return willChange.merge(with: willHide)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private static func overlap(from notification: Notification) -> CGFloat? {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return nil
        }
        let screen = UIScreen.main.bounds
        return max(0, screen.maxY - frame.minY)
    }
}

private struct KeyboardOverlapReader: ViewModifier {
    @Binding var overlap: CGFloat

    func body(content: Content) -> some View {
        content
            .onReceive(Keyboard.overlapPublisher) { next in
                overlap = next
            }
    }
}

private struct KeyboardDoneToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    Keyboard.dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
            }
        }
    }
}

extension View {
    func readsKeyboardOverlap(_ overlap: Binding<CGFloat>) -> some View {
        modifier(KeyboardOverlapReader(overlap: overlap))
    }

    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneToolbar())
    }

    func dismissesKeyboardOnScroll() -> some View {
        scrollDismissesKeyboard(.interactively)
    }
}
