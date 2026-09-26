import SwiftUI
import UIKit

/// Native toolbar gaps do not forward taps to the converter's SwiftUI background.
struct ToolbarTapDismissal: UIViewRepresentable {
  let enabled: Bool
  let onTap: () -> Void

  func makeUIView(context: Context) -> ToolbarTapObserverView {
    ToolbarTapObserverView()
  }

  func updateUIView(_ view: ToolbarTapObserverView, context: Context) {
    view.onTap = onTap
    view.recognizer.isEnabled = enabled
  }

  static func dismantleUIView(_ view: ToolbarTapObserverView, coordinator: ()) {
    view.detach()
  }
}

final class ToolbarTapObserverView: UIView, UIGestureRecognizerDelegate {
  var onTap: (() -> Void)?
  private weak var observedWindow: UIWindow?
  lazy var recognizer: UITapGestureRecognizer = {
    let recognizer = UITapGestureRecognizer(target: self, action: #selector(tapped))
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesEnded = false
    recognizer.delegate = self
    return recognizer
  }()

  init() {
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    backgroundColor = .clear
  }

  required init?(coder: NSCoder) { nil }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    detach()
    observedWindow = window
    window?.addGestureRecognizer(recognizer)
  }

  func detach() {
    observedWindow?.removeGestureRecognizer(recognizer)
    observedWindow = nil
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
  )
    -> Bool
  {
    // Observe only the toolbar above this content view, leaving scrolling and keys alone.
    touch.location(in: self).y < bounds.minY
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }

  @objc private func tapped() { onTap?() }
}
