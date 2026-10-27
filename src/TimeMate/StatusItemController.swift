//  Created by homielab.com

import AppKit
import Combine
import SwiftUI

/// Manages the macOS menu bar status item, its custom SwiftUI hosting view,
/// the right-click menu, and VoiceOver accessibility labels.
final class StatusItemController: NSObject {
  private let timer: PomodoroTimer
  /// What the menu bar view and the VoiceOver label follow; changes only when
  /// something they show changes.
  let menuBarModel: MenuBarModel
  let statusItem: NSStatusItem
  private let menuBarHostingView: PassThroughHostingView
  private var accessibilityLabelUpdates: AnyCancellable?
  private var voiceOverObservation: NSKeyValueObservation?
  private(set) var isVoiceOverRunning = false

  var onTogglePopover: (() -> Void)?
  var onOpenSettings: (() -> Void)?
  var onTickModeNeedsUpdate: (() -> Void)?
  var isPopoverShown: (() -> Bool)?
  var onClosePopover: (() -> Void)?

  init(
    timer: PomodoroTimer,
    hideMenuBarTime: Bool,
    statusItem: NSStatusItem? = nil,
    onTogglePopover: (() -> Void)? = nil,
    onOpenSettings: (() -> Void)? = nil,
    onTickModeNeedsUpdate: (() -> Void)? = nil,
    isPopoverShown: (() -> Bool)? = nil,
    onClosePopover: (() -> Void)? = nil
  ) {
    self.timer = timer
    self.menuBarModel = MenuBarModel(timer: timer)
    let item =
      statusItem
      ?? NSStatusBar.system.statusItem(withLength: MenuBarLayout.width(hideTime: hideMenuBarTime))
    self.statusItem = item
    self.menuBarHostingView = PassThroughHostingView(rootView: AnyView(EmptyView()))
    self.onTogglePopover = onTogglePopover
    self.onOpenSettings = onOpenSettings
    self.onTickModeNeedsUpdate = onTickModeNeedsUpdate
    self.isPopoverShown = isPopoverShown
    self.onClosePopover = onClosePopover
    super.init()

    if let subviews = item.button?.subviews {
      for subview in subviews {
        subview.removeFromSuperview()
      }
    }
    item.button?.addSubview(menuBarHostingView)
    layoutMenuBar(hideTime: hideMenuBarTime)
    item.button?.target = self
    item.button?.action = #selector(statusItemClicked)
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    observeVoiceOverForAccessibilityLabel()
  }

  var statusButton: NSStatusBarButton? {
    statusItem.button
  }

  /// Sizes the status item and updates the menu bar view in place.
  func layoutMenuBar(hideTime: Bool) {
    let width = MenuBarLayout.width(hideTime: hideTime)
    statusItem.length = width
    menuBarHostingView.rootView = AnyView(MenuBarView(model: menuBarModel, hideTime: hideTime))
    menuBarHostingView.frame = NSRect(
      x: 0, y: 0, width: width, height: NSStatusBar.system.thickness)
  }

  /// Left click toggles the popover; right click (or Control-click) opens the menu.
  @objc func statusItemClicked() {
    let event = NSApp.currentEvent
    if StatusItemMenu.opensMenu(
      eventType: event?.type, modifierFlags: event?.modifierFlags ?? [])
    {
      showStatusItemMenu()
    } else {
      onTogglePopover?()
    }
  }

  func showStatusItemMenu() {
    guard let button = statusItem.button else { return }
    if isPopoverShown?() == true {
      onClosePopover?()
    }
    // Attaching the menu only for this click keeps left clicks on the popover
    // and lets the system place and highlight the menu like any menu extra.
    statusItem.menu = makeStatusItemMenu()
    button.performClick(nil)
    statusItem.menu = nil
  }

  /// Built on every right click, so titles follow the timer's current state.
  func makeStatusItemMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(
      menuItem(
        StatusItemMenu.startPauseTitle(
          state: timer.state, isWaitingToContinue: timer.isWaitingToContinue),
        action: #selector(menuStartPause)))
    menu.addItem(menuItem(NSLocalizedString("Skip", comment: ""), action: #selector(menuSkip)))
    let reset = menuItem(NSLocalizedString("Reset", comment: ""), action: #selector(menuReset))
    reset.isEnabled = StatusItemMenu.isResetEnabled(state: timer.state)
    menu.addItem(reset)
    menu.addItem(.separator())
    menu.addItem(
      menuItem(NSLocalizedString("Settings…", comment: ""), action: #selector(menuOpenSettings)))
    menu.addItem(.separator())
    menu.addItem(
      menuItem(
        NSLocalizedString("Quit", comment: ""), action: #selector(NSApplication.terminate(_:)),
        target: NSApp, keyEquivalent: "q"))
    return menu
  }

  private func menuItem(
    _ title: String, action: Selector, target: AnyObject? = nil, keyEquivalent: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = target ?? self
    return item
  }

  @objc private func menuStartPause() { timer.perform(.startPause) }
  @objc private func menuSkip() { timer.perform(.skip) }
  @objc private func menuReset() { timer.stopTimer() }

  @objc private func menuOpenSettings() {
    onOpenSettings?()
  }

  // MARK: - VoiceOver label

  /// VoiceOver reads the menu bar item as "TimeMate, Focus, 12 minutes,
  /// 34 seconds remaining". The label follows the timer only while VoiceOver
  /// is on, so the menu bar does no extra work every second otherwise.
  private func observeVoiceOverForAccessibilityLabel() {
    voiceOverObservation = NSWorkspace.shared.observe(
      \.isVoiceOverEnabled, options: [.initial, .new]
    ) { [weak self] workspace, _ in
      let enabled = workspace.isVoiceOverEnabled
      DispatchQueue.main.async { self?.setAccessibilityLabelUpdates(enabled: enabled) }
    }
  }

  func setAccessibilityLabelUpdates(enabled: Bool) {
    isVoiceOverRunning = enabled
    onTickModeNeedsUpdate?()
    guard enabled else {
      accessibilityLabelUpdates = nil
      statusItem.button?.setAccessibilityLabel(Bundle.main.appName)
      return
    }
    updateStatusItemAccessibilityLabel()
    // objectWillChange fires before the new values land; read them on the next pass.
    accessibilityLabelUpdates = menuBarModel.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.updateStatusItemAccessibilityLabel() }
  }

  func updateStatusItemAccessibilityLabel() {
    let label = menuBarModel.accessibilityLabel
    if statusItem.button?.accessibilityLabel() != label {
      statusItem.button?.setAccessibilityLabel(label)
    }
  }
}
