import CurrencySupport
import SwiftUI
import UIKit

struct TickerQuote: Equatable {
  let code: String
  let amount: String
}

/// A display-link advances only the scroll offset; rate formatting and SwiftUI layout do not run per frame.
struct ConversionTicker: UIViewRepresentable {
  let quotes: [TickerQuote]
  let moving: Bool
  let accessibilitySummary: String
  @Environment(\.sizeCategory) private var sizeCategory
  @Environment(\.colorScheme) private var colorScheme

  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIView(context: Context) -> UIScrollView {
    let scroll = UIScrollView()
    scroll.showsHorizontalScrollIndicator = false
    scroll.alwaysBounceHorizontal = false
    scroll.clipsToBounds = true
    scroll.delegate = context.coordinator
    scroll.accessibilityIdentifier = "onboarding.ticker"
    context.coordinator.scroll = scroll
    let press = UILongPressGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.touch(_:)))
    press.minimumPressDuration = 0
    press.cancelsTouchesInView = false
    press.delegate = context.coordinator
    scroll.addGestureRecognizer(press)
    scroll.addGestureRecognizer(
      UIHoverGestureRecognizer(
        target: context.coordinator, action: #selector(Coordinator.hover(_:))))
    context.coordinator.start()
    return scroll
  }
  func updateUIView(_ scroll: UIScrollView, context: Context) {
    context.coordinator.moving = moving && !UIAccessibility.isVoiceOverRunning
    let key = "\(quotes)|\(sizeCategory)|\(colorScheme)"
    guard context.coordinator.key != key else { return }
    context.coordinator.key = key
    // Content updates keep the current cycle position and velocity. Only direct interaction
    // with the ticker earns a pause; toggling a currency elsewhere must not look stalled.
    let previousWidth = context.coordinator.cycleWidth
    let position =
      previousWidth > 0
      ? max(0, scroll.contentOffset.x).truncatingRemainder(dividingBy: previousWidth) : 0
    let row = TickerRow(quotes: quotes).environment(\.sizeCategory, sizeCategory)
      .environment(\.colorScheme, colorScheme)
    let host = context.coordinator.host ?? UIHostingController(rootView: AnyView(row))
    host.rootView = AnyView(row)
    host.view.backgroundColor = .clear
    let measured = host.sizeThatFits(
      in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 100))
    let width = ceil(measured.width)
    context.coordinator.cycleWidth = width
    context.coordinator.host = host
    if host.view.superview == nil { scroll.addSubview(host.view) }
    host.view.frame = CGRect(x: 0, y: 0, width: width, height: measured.height)
    let duplicate =
      context.coordinator.duplicate
      ?? UIHostingController(rootView: AnyView(row.accessibilityHidden(true)))
    duplicate.rootView = AnyView(row.accessibilityHidden(true))
    duplicate.view.backgroundColor = .clear
    duplicate.view.accessibilityElementsHidden = true
    context.coordinator.duplicate = duplicate
    if duplicate.view.superview == nil { scroll.addSubview(duplicate.view) }
    duplicate.view.frame = CGRect(x: width, y: 0, width: width, height: measured.height)
    scroll.contentSize = CGSize(width: width * 2, height: measured.height)
    scroll.contentOffset.x = width > 0 ? position.truncatingRemainder(dividingBy: width) : 0
    scroll.accessibilityLabel = accessibilitySummary
  }
  static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
    coordinator.link?.invalidate()
  }

  @MainActor final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var scroll: UIScrollView?
    var host: UIHostingController<AnyView>?
    var duplicate: UIHostingController<AnyView>?
    var key = ""
    var cycleWidth: CGFloat = 0
    var moving = false
    var touching = false
    var pauseUntil: CFTimeInterval = 0
    var lastFrame: CFTimeInterval = 0
    var link: CADisplayLink?
    func start() {
      let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
      link.add(to: .main, forMode: .common)
      self.link = link
    }
    @objc func frame(_ sender: CADisplayLink) {
      let delta = lastFrame == 0 ? 0 : min(sender.timestamp - lastFrame, 0.05)
      lastFrame = sender.timestamp
      guard let scroll, scroll.bounds.width > 0 else { return }
      let overflowing = cycleWidth > scroll.bounds.width
      duplicate?.view.isHidden = !overflowing
      scroll.contentSize.width = overflowing ? cycleWidth * 2 : scroll.bounds.width
      if !overflowing {
        host?.view.frame.origin.x = (scroll.bounds.width - cycleWidth) / 2
        scroll.contentOffset.x = 0
      } else {
        host?.view.frame.origin.x = 0
      }
      guard overflowing, moving, !UIAccessibility.isVoiceOverRunning, !touching, !scroll.isDragging,
        !scroll.isDecelerating,
        sender.timestamp >= pauseUntil
      else { return }
      var next = scroll.contentOffset.x + 21 * delta
      if next >= cycleWidth { next -= cycleWidth }
      scroll.contentOffset.x = next
    }
    @objc func hover(_ gesture: UIHoverGestureRecognizer) {
      touching = gesture.state == .began || gesture.state == .changed
      pauseUntil = CACurrentMediaTime() + 2
    }
    @objc func touch(_ gesture: UILongPressGestureRecognizer) {
      touching = gesture.state == .began || gesture.state == .changed
      pauseUntil = CACurrentMediaTime() + 2
    }
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
      pauseUntil = CACurrentMediaTime() + 2
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
      pauseUntil = CACurrentMediaTime() + 2
    }
  }
}

private struct TickerRow: View {
  let quotes: [TickerQuote]
  var body: some View {
    HStack(spacing: 24) {
      ForEach(quotes, id: \.code) { quote in
        HStack(spacing: 8) {
          CurrencyIcon(quote.code, size: 22)
          Text("\(quote.amount) \(quote.code)")
            .font(AppStyle.font(.subheadline, weight: .medium)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
      }
    }
    .padding(.horizontal, 12).frame(minHeight: 44).fixedSize()
  }
}
