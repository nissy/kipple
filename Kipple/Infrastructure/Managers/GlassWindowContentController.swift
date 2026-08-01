//
//  GlassWindowContentController.swift
//  Kipple
//
//  Shared glass-backed window content host.
//

import SwiftUI
import AppKit

@MainActor
final class GlassWindowContentController<Content: View>: NSViewController {
    let hostingController: NSHostingController<Content>

    private let cornerRadius: CGFloat

    init(hostingController: NSHostingController<Content>, cornerRadius: CGFloat) {
        self.hostingController = hostingController
        self.cornerRadius = cornerRadius
        hostingController.sizingOptions = []
        super.init(nibName: nil, bundle: nil)
        addChild(hostingController)
    }

    convenience init(rootView: Content, cornerRadius: CGFloat) {
        self.init(hostingController: NSHostingController(rootView: rootView), cornerRadius: cornerRadius)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        if #available(macOS 26.0, *) {
            view = makeGlassContainer()
        } else {
            view = makeMaterialContainer()
        }
    }

    func hostedFittingSize(fallback: NSSize) -> NSSize {
        hostingController.view.layoutSubtreeIfNeeded()
        var fitting = hostingController.view.fittingSize
        if !fitting.width.isFinite || fitting.width <= 0 { fitting.width = fallback.width }
        if !fitting.height.isFinite || fitting.height <= 0 { fitting.height = fallback.height }
        return fitting
    }

    @available(macOS 26.0, *)
    private func makeGlassContainer() -> NSView {
        let container = makeRoundedContainer()
        let glassView = NSGlassEffectView()
        glassView.style = .regular
        glassView.cornerRadius = cornerRadius
        glassView.tintColor = nil
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = cornerRadius
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true

        prepareHostedView()
        glassView.contentView = hostingController.view
        container.addSubview(glassView)
        pin(glassView, to: container)
        return container
    }

    private func makeMaterialContainer() -> NSView {
        let container = makeRoundedContainer()
        let materialView = NSVisualEffectView()
        materialView.blendingMode = .behindWindow
        materialView.material = .popover
        materialView.state = .active
        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = cornerRadius
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true

        prepareHostedView()
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(hostingController.view)
        container.addSubview(materialView)
        pin(materialView, to: container)
        pin(hostingController.view, to: materialView)
        return container
    }

    private func makeRoundedContainer() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        return container
    }

    private func prepareHostedView() {
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.layer?.cornerRadius = cornerRadius
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true
    }

    private func pin(_ child: NSView, to parent: NSView) {
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}
