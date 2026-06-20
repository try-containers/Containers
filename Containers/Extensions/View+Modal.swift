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
        let presentation = ModalPresentation<Void>(
            current: { isPresented.wrappedValue ? () : nil },
            currentID: { isPresented.wrappedValue ? AnyHashable(true) : nil },
            close: { isPresented.wrappedValue = false }
        )

        return background(
            ModalHost(
                presentation: presentation,
                onDismiss: onDismiss,
                modalContent: { _ in content() }
            )
        )
    }

    func modal<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        let presentation = ModalPresentation<Item>(
            current: { item.wrappedValue },
            currentID: { item.wrappedValue.map { AnyHashable($0.id) } },
            close: { item.wrappedValue = nil }
        )

        return background(
            ModalHost(
                presentation: presentation,
                onDismiss: onDismiss,
                modalContent: content
            )
        )
    }
}

// MARK: - Modal presentation

private struct ModalPresentation<Item> {
    let current: () -> Item?
    let currentID: () -> AnyHashable?
    let close: () -> Void
}

// MARK: - Host

private struct ModalHost<Item, Content: View>: NSViewRepresentable {
    private let cornerRadius: CGFloat = 12

    let presentation: ModalPresentation<Item>
    let onDismiss: (() -> Void)?
    let modalContent: (Item) -> Content

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.presentation = presentation
        context.coordinator.onDismiss = onDismiss

        guard let parentWindow = nsView.window else { return }

        if let item = presentation.current(), let id = presentation.currentID() {
            context.coordinator.present(
                content: AnyView(
                    modalContent(item)
                        .environment(\.close) {
                            presentation.close()
                        }
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .id(id)
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
        Coordinator(presentation: presentation, onDismiss: onDismiss)
    }

    @MainActor
    final class Coordinator {
        var presentation: ModalPresentation<Item>
        var onDismiss: (() -> Void)?

        private let presenter = ModalPresenter()

        init(presentation: ModalPresentation<Item>, onDismiss: (() -> Void)?) {
            self.presentation = presentation
            self.onDismiss = onDismiss
        }

        func present(content: AnyView, from parentWindow: NSWindow) {
            presenter.present(content: content, from: parentWindow) { [weak self] in
                guard let self else { return }
                presentation.close()
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
private final class ModalPresenter {
    private static let parentWindowCornerRadius: CGFloat = 26
    private static let presentationAnimationDuration: TimeInterval = 0.22
    private static let presentationStartScale: CGFloat = 1
    private static let presentationStartYOffset: CGFloat = 50

    /// Minimum top inset used to mimic native sheet placement.
    private static let minTopMargin: CGFloat = 52

    private var panel: NSPanel?
    private var dimmingWindow: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var parentWindowObservers: [NSObjectProtocol] = []
    private var panelObservers: [NSObjectProtocol] = []
    private var onDismiss: (() -> Void)?
    private var isDismissing = false

    /// Prevents panel resize notifications caused by our own repositioning.
    private var isRepositioningPanel = false

    private weak var parentWindow: NSWindow?

    func present(
        content: AnyView,
        from parentWindow: NSWindow,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.onDismiss = onDismiss

        if let hostingView {
            // Visible updates can resize in place.
            hostingView.rootView = content
            self.parentWindow = parentWindow
            updateWindowFrames()
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
            guard self.panel === panel, self.dimmingWindow === dimmingWindow, !self.isDismissing else { return }

            hosting.frame = NSRect(origin: .zero, size: size)
            panel.setContentSize(size)

            await Self.settlePresentedLayout(hostingView: hosting, panel: panel)
            guard self.panel === panel, self.dimmingWindow === dimmingWindow, !self.isDismissing else { return }

            // Apply the settled size before ordering the panel on screen.
            resizePanelToFitContent(panel: panel, hostingView: hosting)

            updateWindowFrames()
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
            finishDismiss(panel: panel, dimmingWindow: dimmingWindow, notify: notify)
        }
    }

    private static func settledFittingSize(
        of hosting: NSHostingView<AnyView>,
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
        hostingView: NSHostingView<AnyView>,
        panel: NSPanel,
        passes: Int = 4
    ) async {
        for _ in 0..<passes {
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }

    private func resizePanelToFitContent(panel: NSPanel, hostingView: NSHostingView<AnyView>) {
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
    }

    private func prepareForPresentation(panel: NSPanel, dimmingWindow: NSWindow) {
        guard let contentView = panel.contentView else { return }

        panel.alphaValue = 0
        dimmingWindow.alphaValue = 0

        contentView.wantsLayer = true
        contentView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let bounds = contentView.bounds
        contentView.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)
        contentView.layer?.transform = CATransform3DMakeScale(
            Self.presentationStartScale, Self.presentationStartScale, 1
        )

        var startFrame = panel.frame
        startFrame.origin.y += Self.presentationStartYOffset
        panel.setFrame(startFrame, display: false)
    }

    private func animateIn(panel: NSPanel, dimmingWindow: NSWindow) async {
        guard let contentView = panel.contentView else { return }

        var restingFrame = panel.frame
        restingFrame.origin.y -= Self.presentationStartYOffset

        await NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.presentationAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
            dimmingWindow.animator().alphaValue = 1
            panel.animator().setFrame(restingFrame, display: true)
            contentView.layer?.transform = CATransform3DIdentity
        }

        // Restore AppKit's normal layer anchor for later live resizes.
        resetContentLayerAnchor(contentView)
    }

    /// Restores the default layer anchor without moving the content.
    private func resetContentLayerAnchor(_ contentView: NSView) {
        guard let layer = contentView.layer else { return }
        let frame = contentView.frame
        layer.anchorPoint = .zero
        layer.position = CGPoint(x: frame.minX, y: frame.minY)
    }

    /// Re-centers the layer anchor for the exit transform without moving it.
    private func recenterContentLayerAnchor(_ contentView: NSView) {
        guard let layer = contentView.layer else { return }
        let frame = layer.frame

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
        CATransaction.commit()
    }

    private func animateOut(panel: NSPanel, dimmingWindow: NSWindow) async {
        guard let contentView = panel.contentView else { return }

        var endFrame = panel.frame
        endFrame.origin.y += Self.presentationStartYOffset

        // Scale out from the visual center.
        recenterContentLayerAnchor(contentView)

        await NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.presentationAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            dimmingWindow.animator().alphaValue = 0
            panel.animator().setFrame(endFrame, display: true)
            contentView.layer?.transform = CATransform3DMakeScale(
                Self.presentationStartScale, Self.presentationStartScale, 1
            )
        }
    }

    private func finishDismiss(panel: NSPanel, dimmingWindow: NSWindow, notify: Bool) {
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
        window.contentView = ModalDimmingView(cornerRadius: Self.parentWindowCornerRadius)
        return window
    }

    private func observeParentWindow(_ parentWindow: NSWindow) {
        let notifications: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification
        ]

        parentWindowObservers = notifications.map { notification in
            NotificationCenter.default.addObserver(
                forName: notification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updateWindowFrames()
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
                    self.updateWindowFrames()
                }
            }
        ]
    }

    private func updateWindowFrames() {
        guard let parentWindow else { return }

        dimmingWindow?.setFrame(parentWindow.frame, display: true)

        if let panel, let hostingView {
            isRepositioningPanel = true
            defer { isRepositioningPanel = false }

            // Re-fit before positioning so the top-margin clamp uses current size.
            resizePanelToFitContent(panel: panel, hostingView: hostingView)

            let parentFrame = parentWindow.frame
            var panelFrame = panel.frame
            panelFrame.origin.x = parentFrame.midX - panelFrame.width / 2
            panelFrame.origin.y = Self.panelOriginY(parentFrame: parentFrame, panelHeight: panelFrame.height)
            panel.setFrame(panelFrame, display: true)
        }
    }

    /// Centers short panels and clamps tall panels below the parent's top edge.
    private static func panelOriginY(parentFrame: NSRect, panelHeight: CGFloat) -> CGFloat {
        let centeredTopMargin = (parentFrame.height - panelHeight) / 2
        let topMargin = max(minTopMargin, centeredTopMargin)
        return parentFrame.maxY - topMargin - panelHeight
    }
}

// MARK: - Dimming overlay

private final class ModalDimmingView: NSView {
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
        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.withAlphaComponent(0.22).setFill()
        path.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }
}
