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
  private var toolTipTag: NSView.ToolTipTag?
  private(set) var isVoiceOverRunning = false

  var onTogglePopover: (() -> Void)?
  var onOpenSettings: (() -> Void)?
  var onTickModeNeedsUpdate: (() -> Void)?
  var isPopoverShown: (() -> Bool)?
  var onClosePopover: (() -> Void)?

  init(
    timer: PomodoroTimer,
    menuBarStyle: MenuBarTimeStyle,
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
      ?? NSStatusBar.system.statusItem(withLength: MenuBarLayout.width(style: menuBarStyle))
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
    layoutMenuBar(style: menuBarStyle)
    item.button?.target = self
    item.button?.action = #selector(statusItemClicked)
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    observeVoiceOverForAccessibilityLabel()
  }

  /// Puts the icon back in the menu bar after the user ⌘-dragged it out.
  func showStatusItem() {
    if !statusItem.isVisible { statusItem.isVisible = true }
  }

  var statusButton: NSStatusBarButton? {
    statusItem.button
  }

  /// Sizes the status item and updates the menu bar view in place.
  func layoutMenuBar(style: MenuBarTimeStyle) {
    let width = MenuBarLayout.width(style: style)
    statusItem.length = width
    menuBarHostingView.rootView = AnyView(MenuBarView(model: menuBarModel, style: style))
    menuBarHostingView.frame = NSRect(
      x: 0, y: 0, width: width, height: NSStatusBar.system.thickness)
    updateToolTip(width: width)
  }

  /// Hovering the item shows the same sentence VoiceOver reads, e.g. "TimeMate,
  /// Focus, 12 minutes, 34 seconds remaining". The text is produced when the
  /// tooltip appears (`view(_:stringForToolTip:...)`), so nothing runs per tick.
  private func updateToolTip(width: CGFloat) {
    guard let button = statusItem.button else { return }
    if let toolTipTag {
      button.removeToolTip(toolTipTag)
    }
    toolTipTag = button.addToolTip(
      NSRect(x: 0, y: 0, width: width, height: NSStatusBar.system.thickness),
      owner: self, userData: nil)
  }

  func view(
    _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
    userData data: UnsafeMutableRawPointer?
  ) -> String {
    menuBarModel.tooltipText()
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
  @objc private func menuReset() {
    guard timer.skipLockSeconds == 0 else {
      NSSound.beep()
      return
    }
    guard timer.resetNeedsConfirmation else {
      timer.stopTimer()
      return
    }
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("Reset the focus session?", comment: "")
    alert.informativeText = NSLocalizedString(
      "More than half of this focus session has run.", comment: "")
    alert.addButton(withTitle: NSLocalizedString("Record and Reset", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("Reset Without Recording", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
    NSApp.activate(ignoringOtherApps: true)
    switch alert.runModal() {
    case .alertFirstButtonReturn: timer.stopTimer(recording: true)
    case .alertSecondButtonReturn: timer.stopTimer()
    default: break
    }
  }

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
    // `TickMode.mode(...)` reads `isVoiceOverRunning` when the tick mode is updated.
    isVoiceOverRunning = enabled
    onTickModeNeedsUpdate?()
    switch StatusItemPolicy.label(voiceOverEnabled: enabled, appName: Bundle.main.appName) {
    case .fixed(let label):
      accessibilityLabelUpdates = nil
      statusItem.button?.setAccessibilityLabel(label)
    case .followsTimer:
      updateStatusItemAccessibilityLabel()
      // objectWillChange fires before the new values land; read them on the next pass.
      accessibilityLabelUpdates = menuBarModel.objectWillChange
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.updateStatusItemAccessibilityLabel() }
    }
  }

  func updateStatusItemAccessibilityLabel() {
    if let label = StatusItemPolicy.labelUpdate(
      current: statusItem.button?.accessibilityLabel(), new: menuBarModel.accessibilityLabel)
    {
      statusItem.button?.setAccessibilityLabel(label)
    }
  }
}
