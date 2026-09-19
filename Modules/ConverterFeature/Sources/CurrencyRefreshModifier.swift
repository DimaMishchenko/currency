import CurrencySupport
import SwiftUI
import UIKit

/// Attach inside the scroll content so UIKit owns the refresh inset and its spring-back.
struct CurrencyRefreshAttachment: UIViewRepresentable {
  let refreshing: Bool
  let enabled: Bool
  let action: () async -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  func makeUIView(context: Context) -> AttachmentView {
    let view = AttachmentView()
    view.attach = { [weak coordinator = context.coordinator] view in coordinator?.attach(from: view)
    }
    return view
  }

  func updateUIView(_ view: AttachmentView, context: Context) {
    let coordinator = context.coordinator
    coordinator.action = action
    coordinator.enabled = enabled && scenePhase == .active
    coordinator.state.reducedMotion = reduceMotion
    coordinator.state.active = coordinator.enabled
    coordinator.control.isEnabled = coordinator.enabled
    coordinator.attach(from: view)
    coordinator.sync(refreshing: refreshing)
  }

  func makeCoordinator() -> Coordinator { Coordinator() }
  static func dismantleUIView(_ view: AttachmentView, coordinator: Coordinator) {
    coordinator.detach()
  }

  final class AttachmentView: UIView {
    var attach: ((UIView) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); attach?(self) }
    override func didMoveToSuperview() { super.didMoveToSuperview(); attach?(self) }
    override func layoutSubviews() { super.layoutSubviews(); attach?(self) }
  }

  @MainActor @Observable final class Presentation {
    var pulling = false
    var active = false
    var started: Date?
    var reducedMotion = false
  }

  struct Symbol: View {
    let state: Presentation
    var body: some View {
      CurrencySymbolLoader(
        moving: !state.reducedMotion && (state.pulling || state.started != nil),
        interval: .milliseconds(400),
        animateImmediately: true
      )
      .foregroundStyle(.secondary)
      .environment(\.scenePhase, state.active ? .active : .inactive)
      .accessibilityHidden(true)
    }
  }

  @MainActor final class Coordinator: NSObject {
    let control = UIRefreshControl()
    let state = Presentation()
    lazy var host = UIHostingController(rootView: Symbol(state: state))
    weak var scroll: UIScrollView?
    var observation: NSKeyValueObservation?
    var action: (() async -> Void)?
    var enabled = true
    var task: Task<Void, Never>?
    var finishTask: Task<Void, Never>?
    var externalRefreshing = false
    var ending = false
    var revision = 0
    var restingTopInset: CGFloat = 0

    override init() {
      super.init()
      control.tintColor = .clear
      control.addTarget(self, action: #selector(refresh), for: .valueChanged)
      guard let view = host.view else { return }
      view.backgroundColor = .clear
      view.isUserInteractionEnabled = false
      view.translatesAutoresizingMaskIntoConstraints = false
      control.addSubview(view)
      NSLayoutConstraint.activate([
        view.centerXAnchor.constraint(equalTo: control.centerXAnchor),
        view.centerYAnchor.constraint(equalTo: control.centerYAnchor),
        view.widthAnchor.constraint(equalToConstant: 40),
        view.heightAnchor.constraint(equalToConstant: 40)
      ])
    }

    func attach(from view: UIView) {
      var ancestor = view.superview
      while let candidate = ancestor {
        if let scroll = candidate as? UIScrollView {
          guard self.scroll !== scroll else {
            if scroll.refreshControl !== control { scroll.refreshControl = control }
            return
          }
          detach()
          self.scroll = scroll
          restingTopInset = scroll.adjustedContentInset.top
          scroll.refreshControl = control
          observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updatePull() }
          }
          return
        }
        ancestor = candidate.superview
      }
    }

    func updatePull() {
      guard let scroll, state.started == nil else { return }
      // UIKit adds the refresh inset before valueChanged; keep the reveal distance stable.
      let distance = max(0, -(scroll.contentOffset.y + restingTopInset))
      if distance < 1, !scroll.isDragging, !control.isRefreshing {
        restingTopInset = scroll.adjustedContentInset.top
      }
      if ending {
        if distance < 1 { ending = false }
        return
      }
      state.pulling = distance > 1
      host.view.alpha = min(1, distance / 24)
    }

    func sync(refreshing: Bool) {
      guard enabled else {
        revision += 1
        externalRefreshing = false
        task?.cancel(); task = nil
        finishTask?.cancel(); finishTask = nil
        state.started = nil
        state.pulling = false
        control.endRefreshing()
        return
      }
      guard refreshing != externalRefreshing else { return }
      externalRefreshing = refreshing
      if refreshing {
        start()
      } else if task == nil {
        finish()
      }
    }

    func start() {
      finishTask?.cancel()
      revision += 1
      ending = false
      host.view.layer.removeAllAnimations()
      host.view.alpha = 1
      if state.started == nil { state.started = .now }
      control.beginRefreshing()
    }

    @objc func refresh() {
      guard enabled, task == nil else { return }
      start()
      task = Task { [weak self] in
        guard let self else { return }
        await action?()
        guard !Task.isCancelled else { return }
        task = nil
        finish()
      }
    }

    func finish() {
      guard let started = state.started else { return }
      finishTask?.cancel()
      let revision = revision
      finishTask = Task { [weak self] in
        let remaining = max(0, 1.1 - Date.now.timeIntervalSince(started))
        do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
        guard let self, !Task.isCancelled else { return }
        // A fast cached response must not collapse the control underneath an active pull.
        while self.scroll?.isDragging == true {
          do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
        }
        UIView.animate(withDuration: state.reducedMotion ? 0.15 : 0.25) {
          self.host.view.alpha = 0
        } completion: { [weak self] _ in
          guard let self, self.revision == revision, !self.externalRefreshing, self.task == nil
          else { return }
          self.ending = true
          self.control.endRefreshing()
          self.state.started = nil
          self.state.pulling = false
        }
      }
    }

    func detach() {
      revision += 1
      task?.cancel(); task = nil
      finishTask?.cancel(); finishTask = nil
      observation = nil
      control.endRefreshing()
      if scroll?.refreshControl === control { scroll?.refreshControl = nil }
      scroll = nil
      state.started = nil
      state.pulling = false
    }
  }
}
