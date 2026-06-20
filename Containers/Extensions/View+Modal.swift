//
//  Modal.swift
//  Containers
//

import AppKit
import SwiftUI

// MARK: - Environment

private struct CloseEnvironmentKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var close: () -> Void {
        get { self[CloseEnvironmentKey.self] }
        set { self[CloseEnvironmentKey.self] = newValue }
    }
}

// MARK: - Public API

extension View {
    func modal<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(
            Modal(
                id: { isPresented.wrappedValue ? AnyHashable(true) : nil },
                current: { isPresented.wrappedValue ? () : nil },
                close: { isPresented.wrappedValue = false },
                onDismiss: onDismiss,
                content: content
            )
        )
    }

    func modal<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        background(
            Modal(
                id: { item.wrappedValue.map { AnyHashable($0.id) } },
                current: { item.wrappedValue },
                close: { item.wrappedValue = nil },
                onDismiss: onDismiss,
                content: content
            )
        )
    }
}

// MARK: - Host

private struct ModalContent<Content: View>: View {
    private let cornerRadius: CGFloat = 12

    let id: AnyHashable
    let close: () -> Void
    let content: Content

    var body: some View {
        content
            .environment(\.close, close)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .id(id)
    }
}

private struct Modal<Item, Content: View>: NSViewRepresentable {
    typealias PresentedContent = ModalContent<Content>

    let id: () -> AnyHashable?
    let current: () -> Item?
    let close: () -> Void
    let onDismiss: (() -> Void)?
    let content: (Item) -> Content

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.close = close
        context.coordinator.onDismiss = onDismiss

        guard let parentWindow = nsView.window else { return }

        if let item = current(), let id = id() {
            context.coordinator.present(
                content: ModalContent(
                    id: id,
                    close: close,
                    content: content(item)
                ),
                from: parentWindow
            )
        } else {
            context.coordinator.dismiss(notify: true)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss(notify: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(close: close, onDismiss: onDismiss)
    }

    @MainActor
    final class Coordinator {
        var close: () -> Void
        var onDismiss: (() -> Void)?

        private let presenter = ModalPresenter<PresentedContent>()

        init(close: @escaping () -> Void, onDismiss: (() -> Void)?) {
            self.close = close
            self.onDismiss = onDismiss
        }

        func present(content: PresentedContent, from parentWindow: NSWindow) {
            presenter.present(content: content, from: parentWindow) {
                [weak self] in
                guard let self else { return }
                close()
                onDismiss?()
            }
        }

        func dismiss(notify: Bool) {
            presenter.dismiss(notify: notify)
        }
    }
}

// MARK: - Presenter

@MainActor
private final class ModalPresenter<PresentedContent: View> {
    private static var parentWindowCornerRadius: CGFloat { 26 }
    private static var presentationAnimationDuration: TimeInterval { 0.22 }
    private static var presentationStartYOffset: CGFloat { 50 }

    /// Minimum top inset used to mimic native sheet placement.
    private static var minTopMargin: CGFloat { 50 }

    private var panel: NSPanel?
    private var dimmingWindow: NSWindow?
    private var hostingView: NSHostingView<PresentedContent>?
    private var parentWindowObservers: [NSObjectProtocol] = []
    private var panelObservers: [NSObjectProtocol] = []
    private var onDismiss: (() -> Void)?
    private var isDismissing = false

    /// Prevents panel resize notifications caused by our own repositioning.
    private var isRepositioningPanel = false

    private weak var parentWindow: NSWindow?

    func present(
        content: PresentedContent,
        from parentWindow: NSWindow,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.onDismiss = onDismiss

        if let hostingView {
            // Visible updates can resize in place.
            hostingView.rootView = content
            self.parentWindow = parentWindow
            updateWindowFrames(fitContent: true)
            return
        }

        let dimmingWindow = makeDimmingWindow(for: parentWindow)
        let panel = makePanel()
        let hosting = NSHostingView(rootView: content)
        panel.contentView = hosting

        self.panel = panel
        self.dimmingWindow = dimmingWindow
        self.hostingView = hosting
        self.parentWindow = parentWindow
        self.isDismissing = false

        observeParentWindow(parentWindow)
        observePanel(panel)

        Task { @MainActor in
            // Resolve SwiftUI layout off-screen before the panel is visible.
            let size = await Self.settledFittingSize(of: hosting)
            guard self.panel === panel, self.dimmingWindow === dimmingWindow,
                !self.isDismissing
            else { return }

            hosting.frame = NSRect(origin: .zero, size: size)
            panel.setContentSize(size)

            await Self.settlePresentedLayout(hostingView: hosting, panel: panel)
            guard self.panel === panel, self.dimmingWindow === dimmingWindow,
                !self.isDismissing
            else { return }

            // Apply the settled size before ordering the panel on screen.
            resizePanelToFitContent(panel: panel, hostingView: hosting)

            updateWindowFrames(fitContent: false)
            prepareForPresentation(panel: panel, dimmingWindow: dimmingWindow)

            // Show only after measurement is stable.
            parentWindow.addChildWindow(dimmingWindow, ordered: .above)
            parentWindow.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
            dimmingWindow.orderFront(nil)

            await animateIn(panel: panel, dimmingWindow: dimmingWindow)
        }
    }

    func dismiss(notify: Bool) {
        guard let panel, let dimmingWindow, !isDismissing else { return }
        isDismissing = true

        Task { @MainActor in
            await animateOut(panel: panel, dimmingWindow: dimmingWindow)
            finishDismiss(
                panel: panel,
                dimmingWindow: dimmingWindow,
                notify: notify
            )
        }
    }

    private static func settledFittingSize(
        of hosting: NSHostingView<PresentedContent>,
        maxAttempts: Int = 10
    ) async -> NSSize {
        var previous = hosting.fittingSize
        for _ in 0..<maxAttempts {
            await Task.yield()
            let current = hosting.fittingSize
            if current == previous {
                return current
            }
            previous = current
        }
        return previous
    }

    /// Lets SwiftUI layout converge before the panel is shown.
    private static func settlePresentedLayout(
        hostingView: NSHostingView<PresentedContent>,
        panel: NSPanel,
        passes: Int = 4
    ) async {
        for _ in 0..<passes {
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }

    private func resizePanelToFitContent(
        panel: NSPanel,
        hostingView: NSHostingView<PresentedContent>
    ) {
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
    }

    private func prepareForPresentation(panel: NSPanel, dimmingWindow: NSWindow)
    {
        panel.alphaValue = 0
        dimmingWindow.alphaValue = 0

        var startFrame = panel.frame
        startFrame.origin.y += Self.presentationStartYOffset
        panel.setFrame(startFrame, display: false)
    }

    private func animateIn(panel: NSPanel, dimmingWindow: NSWindow) async {
        var restingFrame = panel.frame
        restingFrame.origin.y -= Self.presentationStartYOffset

        await NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.presentationAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
            dimmingWindow.animator().alphaValue = 1
            panel.animator().setFrame(restingFrame, display: true)
        }
    }

    private func animateOut(panel: NSPanel, dimmingWindow: NSWindow) async {
        var endFrame = panel.frame
        endFrame.origin.y += Self.presentationStartYOffset

        await NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.presentationAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            dimmingWindow.animator().alphaValue = 0
            panel.animator().setFrame(endFrame, display: true)
        }
    }

    private func finishDismiss(
        panel: NSPanel,
        dimmingWindow: NSWindow,
        notify: Bool
    ) {
        parentWindowObservers.forEach(NotificationCenter.default.removeObserver)
        parentWindowObservers = []

        panelObservers.forEach(NotificationCenter.default.removeObserver)
        panelObservers = []

        parentWindow?.removeChildWindow(dimmingWindow)
        dimmingWindow.orderOut(nil)

        parentWindow?.removeChildWindow(panel)
        panel.orderOut(nil)

        let onDismiss = self.onDismiss

        self.onDismiss = nil
        self.panel = nil
        self.dimmingWindow = nil
        self.hostingView = nil
        self.parentWindow = nil
        self.isDismissing = false

        if notify {
            onDismiss?()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        return panel
    }

    private func makeDimmingWindow(for parentWindow: NSWindow) -> NSWindow {
        let window = NSWindow(
            contentRect: parentWindow.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.animationBehavior = .none
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.contentView = DimmingView(
            cornerRadius: Self.parentWindowCornerRadius
        )
        return window
    }

    private func observeParentWindow(_ parentWindow: NSWindow) {
        let notifications: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
        ]

        parentWindowObservers = notifications.map { notification in
            NotificationCenter.default.addObserver(
                forName: notification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updateWindowFrames(fitContent: true)
                }
            }
        }
    }

    /// Re-applies sheet-style placement after intrinsic content resizes.
    private func observePanel(_ panel: NSPanel) {
        panelObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isRepositioningPanel else { return }
                    self.updateWindowFrames(fitContent: false)
                }
            }
        ]
    }

    private func updateWindowFrames(fitContent: Bool) {
        guard let parentWindow else { return }

        dimmingWindow?.setFrame(parentWindow.frame, display: true)

        if let panel {
            isRepositioningPanel = true
            defer { isRepositioningPanel = false }

            if fitContent, let hostingView {
                resizePanelToFitContent(panel: panel, hostingView: hostingView)
            }

            let parentFrame = parentWindow.frame
            var panelFrame = panel.frame
            panelFrame.origin.x = parentFrame.midX - panelFrame.width / 2
            panelFrame.origin.y = Self.panelOriginY(
                parentFrame: parentFrame,
                panelHeight: panelFrame.height
            )
            panel.setFrame(panelFrame, display: true)
        }
    }

    /// Centers short panels and clamps tall panels below the parent's top edge.
    private static func panelOriginY(parentFrame: NSRect, panelHeight: CGFloat)
        -> CGFloat
    {
        let centeredTopMargin = (parentFrame.height - panelHeight) / 2
        let topMargin = max(minTopMargin, centeredTopMargin)
        return parentFrame.maxY - topMargin - panelHeight
    }
}

// MARK: - Dimming overlay

private final class DimmingView: NSView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        needsDisplay = true
    }

    required init?(coder: NSCoder) {
        self.cornerRadius = 26
        super.init(coder: coder)
        wantsLayer = true
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        NSColor.black.withAlphaComponent(0.22).setFill()
        path.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }
}
