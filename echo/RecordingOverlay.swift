//
//  RecordingOverlay.swift
//  echo
//
//  A small floating indicator shown while echo is recording / transcribing.
//  Implemented as a borderless, non-activating NSPanel hosting a SwiftUI view
//  (the planned architecture for the recording overlay). It never takes focus,
//  ignores the mouse, and floats above other apps on all Spaces.
//

import AppKit
import SwiftUI

@MainActor
final class RecordingOverlay {
    private let controller: DictationController
    private var panel: NSPanel?

    init(controller: DictationController) {
        self.controller = controller
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        reposition(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 48),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false

        let host = NSHostingView(rootView: RecordingOverlayView(controller: controller))
        host.frame = p.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        return p
    }

    private func reposition(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.minY + 120
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct RecordingOverlayView: View {
    let controller: DictationController
    @State private var pulse = false

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { pulse = true }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .recording:
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(.red)
                .frame(width: 18, height: 18)
                .opacity(pulse ? 0.1 : 1)
                .scaleEffect(pulse ? 0.85 : 1)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
        case .transcribing:
            ThreeDotsView()
        case .idle:
            EmptyView()
        }
    }
}

private struct ThreeDotsView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .opacity(animate ? 1 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
