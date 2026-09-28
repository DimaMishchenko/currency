import SwiftUI
import TipKit
import UIKit

@MainActor
struct WidgetTipPopoverAnchor: UIViewRepresentable {
  let tip: ExploreWidgetsTip
  @Binding var isPresented: Bool
  let presented: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(isPresented: $isPresented, tip: tip, presented: presented)
  }

  func makeUIView(context: Context) -> AnchorView {
    let view = AnchorView()
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    view.onWindowChange = { [weak coordinator = context.coordinator, weak view] in
      guard let view else { return }
      if view.window == nil {
        coordinator?.dismiss(clearRequest: true)
      } else {
        coordinator?.schedulePresentation(from: view)
      }
    }
    return view
  }

  func updateUIView(_ view: AnchorView, context: Context) {
    context.coordinator.isPresented = $isPresented
    context.coordinator.presented = presented
    if isPresented {
      context.coordinator.schedulePresentation(from: view)
    } else {
      context.coordinator.dismiss()
    }
  }

  static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
    view.onWindowChange = nil
    coordinator.dismiss(clearRequest: true)
  }

  final class AnchorView: UIView {
    var onWindowChange: (() -> Void)?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      onWindowChange?()
    }
  }

  final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
    var isPresented: Binding<Bool>
    var presented: () -> Void
    private let tip: ExploreWidgetsTip
    private var host: UIHostingController<AnyView>?
    private var presentationTask: Task<Void, Never>?

    init(isPresented: Binding<Bool>, tip: ExploreWidgetsTip, presented: @escaping () -> Void) {
      self.isPresented = isPresented
      self.tip = tip
      self.presented = presented
    }

    func schedulePresentation(from anchor: UIView) {
      guard isPresented.wrappedValue, host == nil, presentationTask == nil else { return }
      presentationTask = Task { [weak self, weak anchor] in
        await Task.yield()
        guard !Task.isCancelled, let self, let anchor else { return }
        self.presentationTask = nil
        self.presentNow(from: anchor)
      }
    }

    private func presentNow(from anchor: UIView) {
      guard isPresented.wrappedValue, anchor.window != nil,
        let controller = presentingController(for: anchor),
        controller.presentedViewController == nil
      else { return }
      let content = HomeDiscoveryPopover(
        tip: tip, presented: { [weak self] in self?.presented() },
        dismissed: { [weak self] in self?.isPresented.wrappedValue = false }
      )
      .multilineTextAlignment(.leading)
      let host = UIHostingController(rootView: AnyView(content))
      host.modalPresentationStyle = .popover
      let fitting = host.sizeThatFits(in: CGSize(width: 320, height: 1_000))
      host.preferredContentSize = CGSize(width: 320, height: max(100, fitting.height))
      guard let popover = host.popoverPresentationController else { return }
      popover.sourceView = anchor
      popover.sourceRect = CGRect(x: anchor.bounds.midX, y: anchor.bounds.maxY, width: 1, height: 1)
      popover.permittedArrowDirections = .up
      popover.delegate = self
      self.host = host
      controller.present(host, animated: true)
    }

    private func presentingController(for anchor: UIView) -> UIViewController? {
      var responder: UIResponder? = anchor
      while let next = responder?.next {
        if let controller = next as? UIViewController { return controller }
        responder = next
      }
      return anchor.window?.rootViewController
    }

    func dismiss(clearRequest: Bool = false) {
      presentationTask?.cancel()
      presentationTask = nil
      host?.dismiss(animated: true)
      host = nil
      if clearRequest && isPresented.wrappedValue {
        let binding = isPresented
        Task { @MainActor in binding.wrappedValue = false }
      }
    }

    func adaptivePresentationStyle(
      for controller: UIPresentationController
    )
      -> UIModalPresentationStyle
    {
      .none
    }

    func popoverPresentationControllerDidDismissPopover(
      _ popoverPresentationController: UIPopoverPresentationController
    ) {
      host = nil
      isPresented.wrappedValue = false
    }
  }
}
