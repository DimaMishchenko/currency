import Testing
import UIKit

@testable import HomeUI

@MainActor
struct CurrencyRefreshAttachmentTests {
  @Test func nativeRefreshInsetDoesNotInterruptPullPresentation() {
    let coordinator = CurrencyRefreshAttachment.Coordinator()
    let scroll = UIScrollView()
    let attachment = UIView()
    scroll.addSubview(attachment)
    coordinator.attach(from: attachment)
    scroll.contentOffset.y = -90
    coordinator.updatePull()
    #expect(coordinator.state.pulling)
    scroll.contentInset.top = 60
    scroll.contentOffset.y = -90
    coordinator.updatePull()
    #expect(coordinator.state.pulling)
    coordinator.detach()
  }

  @Test func refreshAttachmentRecoversAfterScrollViewReconfiguration() {
    let coordinator = CurrencyRefreshAttachment.Coordinator()
    let scroll = UIScrollView()
    let attachment = UIView()
    scroll.addSubview(attachment)
    coordinator.attach(from: attachment)
    #expect(scroll.refreshControl === coordinator.control)
    scroll.refreshControl = nil
    coordinator.attach(from: attachment)
    #expect(scroll.refreshControl === coordinator.control)
    coordinator.start()
    coordinator.detach()
    #expect(scroll.refreshControl == nil)
    #expect(coordinator.state.started == nil)
  }

  @Test func disabledRefreshCanResumeWhenSceneReactivates() {
    let coordinator = CurrencyRefreshAttachment.Coordinator()
    coordinator.sync(refreshing: true)
    #expect(coordinator.state.started != nil)
    coordinator.enabled = false
    coordinator.sync(refreshing: true)
    #expect(coordinator.state.started == nil)
    coordinator.enabled = true
    coordinator.sync(refreshing: true)
    #expect(coordinator.state.started != nil)
    coordinator.detach()
  }

}
