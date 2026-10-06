import MessageUI
import SwiftUI

struct FeedbackMailComposer: UIViewControllerRepresentable {
  let onDismiss: (Bool) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

  func makeUIViewController(context: Context) -> MFMailComposeViewController {
    let controller = MFMailComposeViewController()
    controller.setToRecipients(["dimasike.dev@gmail.com"])
    controller.mailComposeDelegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

  final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
    private let onDismiss: (Bool) -> Void

    init(onDismiss: @escaping (Bool) -> Void) { self.onDismiss = onDismiss }

    func mailComposeController(
      _ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult,
      error: Error?
    ) {
      onDismiss(result == .failed || error != nil)
    }
  }
}
