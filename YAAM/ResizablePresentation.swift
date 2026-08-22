//  ResizablePresentation.swift
//  YAAM

import SwiftUI
import AppKit

private struct ResizableWindowConfigurator: NSViewRepresentable {
    let minimumSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.resizable)
        window.contentMinSize = NSSize(
            width: max(window.contentMinSize.width, minimumSize.width),
            height: max(window.contentMinSize.height, minimumSize.height)
        )
    }
}

extension View {
    func resizablePresentation(minWidth: CGFloat, minHeight: CGFloat) -> some View {
        background(
            ResizableWindowConfigurator(
                minimumSize: NSSize(width: minWidth, height: minHeight)
            )
            .frame(width: 0, height: 0)
        )
    }
}
