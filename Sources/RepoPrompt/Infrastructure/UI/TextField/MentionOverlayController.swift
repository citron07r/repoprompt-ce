import AppKit
import SwiftUI

/// Thin UI layer that renders the floating suggestion popup.
/// Owns *only* view-code; no model / search / navigation logic.
@MainActor
final class MentionOverlayController {
    enum Placement {
        case above
        case below
    }

    var placement: Placement = .below
    var suggestedWidth: CGFloat = 240
    var visibleRowLimit: Int = 5 {
        didSet {
            let normalizedLimit = Self.normalizedVisibleRowLimit(visibleRowLimit)
            if visibleRowLimit != normalizedLimit {
                visibleRowLimit = normalizedLimit
            }
            for window in windows {
                window.setVisibleRowLimit(normalizedLimit)
            }
            enforceScreenBounds()
        }
    }

    /// Remember latest caret rect so we can re-anchor after every resize.
    private var latestCaretRect: NSRect?

    // MARK: – Public API -----------------------------------------------------

    /// Show a brand-new overlay near `caret` with an initial set of items
    /// and attach it to `owner` so it closes/moves with the parent window.
    func show(
        at caret: NSRect,
        owner: NSWindow,
        items: [MentionSuggestion]
    ) {
        prepareRootWindowIfNeeded(owner: owner)
        guard let root = windows.first else { return }

        latestCaretRect = caret
        enforceScreenBounds()

        root.orderFront(nil)
        root.alphaValue = 1
        update(items: items, highlighted: 0)
    }

    /// Re-aligns the root window to the current caret (call after each resize
    /// or when the caret moved horizontally while typing).
    func repositionRoot(to caret: NSRect) {
        latestCaretRect = caret
        enforceScreenBounds()
    }

    /// Replace the list of rows in the *current* level.
    func update(items: [MentionSuggestion], highlighted: Int) {
        guard let win = windows.last else { return }
        win.updateSuggestions(items, highlighted: highlighted)
        enforceScreenBounds()
    }

    /// Move selection by ±delta in the *current* level.
    func moveHighlight(by delta: Int) {
        windows.last?.moveHighlight(delta: delta)
    }

    /// Push a new level (drill-down into folder). Automatically positioned.
    func pushLevel() {
        guard let previous = windows.last else { return }
        let w = SuggestionWindow(
            parent: previous.parentTextView,
            placement: placement,
            width: suggestedWidth,
            visibleRowLimit: Self.normalizedVisibleRowLimit(visibleRowLimit)
        )
        windows.append(w)
        chainWindow(w, after: previous)
        enforceScreenBounds()
    }

    /// Pop the deepest overlay level (go up one folder).
    func popLevel() {
        guard windows.count > 1 else { return }
        let win = windows.removeLast()
        win.orderOut(nil)
        win.parent?.removeChildWindow(win)
    }

    /// Close *all* overlay windows.
    func hide() {
        for w in windows {
            w.orderOut(nil)
            w.parent?.removeChildWindow(w)
        }
        windows.removeAll()
        ownerWindow = nil
        latestCaretRect = nil
    }

    // MARK: – Private --------------------------------------------------------

    private weak var ownerWindow: NSWindow?
    private var windows: [SuggestionWindow] = []

    private func prepareRootWindowIfNeeded(owner: NSWindow) {
        guard windows.isEmpty else { return }
        ownerWindow = owner
        let root = SuggestionWindow(
            parent: nil,
            placement: placement,
            width: suggestedWidth,
            visibleRowLimit: Self.normalizedVisibleRowLimit(visibleRowLimit)
        )
        owner.addChildWindow(root, ordered: .above)
        windows.append(root)
    }

    private static func normalizedVisibleRowLimit(_ limit: Int) -> Int {
        max(limit, 1)
    }

    static func positionedRootFrame(
        caret: NSRect,
        popupSize: NSSize,
        placement: Placement,
        visibleFrame: NSRect?
    ) -> NSRect {
        var frame = NSRect(origin: .zero, size: popupSize)
        switch placement {
        case .above:
            frame.origin = NSPoint(x: caret.minX, y: caret.maxY + 4)
        case .below:
            frame.origin = NSPoint(x: caret.minX, y: caret.minY - 2 - popupSize.height)
        }
        return clampedFrame(frame, to: visibleFrame)
    }

    static func positionedChildFrame(
        after previousFrame: NSRect,
        popupSize: NSSize,
        placement: Placement,
        visibleFrame: NSRect?
    ) -> NSRect {
        var frame = NSRect(origin: .zero, size: popupSize)
        switch placement {
        case .above:
            frame.origin = NSPoint(x: previousFrame.maxX + 4, y: previousFrame.minY)
        case .below:
            frame.origin = NSPoint(x: previousFrame.maxX - 1, y: previousFrame.maxY - popupSize.height)
        }

        if let visibleFrame,
           frame.maxX > visibleFrame.maxX
        {
            let leftX = previousFrame.minX - popupSize.width - 4
            if leftX >= visibleFrame.minX {
                frame.origin.x = leftX
            }
        }

        return clampedFrame(frame, to: visibleFrame)
    }

    static func clampedFrame(_ frame: NSRect, to visibleFrame: NSRect?) -> NSRect {
        guard let visibleFrame else { return frame }
        var clamped = frame

        if clamped.width <= visibleFrame.width {
            clamped.origin.x = min(max(clamped.minX, visibleFrame.minX), visibleFrame.maxX - clamped.width)
        } else {
            clamped.origin.x = visibleFrame.minX
        }

        if clamped.height <= visibleFrame.height {
            clamped.origin.y = min(max(clamped.minY, visibleFrame.minY), visibleFrame.maxY - clamped.height)
        } else {
            clamped.origin.y = visibleFrame.minY
        }

        return clamped
    }

    private func chainWindow(_ w: SuggestionWindow, after prev: NSWindow) {
        let parentWin = prev.parent ?? prev
        parentWin.addChildWindow(w, ordered: .above)
        w.orderFront(nil)
        w.setFrame(
            Self.positionedChildFrame(
                after: prev.frame,
                popupSize: w.frame.size,
                placement: placement,
                visibleFrame: visibleFrame
            ),
            display: true
        )
        w.alphaValue = 1
    }

    private var visibleFrame: NSRect? {
        ownerWindow?.screen?.visibleFrame
    }

    private func enforceScreenBounds() {
        guard !windows.isEmpty else { return }
        if let root = windows.first,
           let caret = latestCaretRect
        {
            root.setFrame(
                Self.positionedRootFrame(
                    caret: caret,
                    popupSize: root.frame.size,
                    placement: placement,
                    visibleFrame: visibleFrame
                ),
                display: true
            )
        }

        guard windows.count > 1 else { return }
        for idx in 1 ..< windows.count {
            let previous = windows[idx - 1]
            let current = windows[idx]
            current.setFrame(
                Self.positionedChildFrame(
                    after: previous.frame,
                    popupSize: current.frame.size,
                    placement: placement,
                    visibleFrame: visibleFrame
                ),
                display: true
            )
        }
    }
}

// ==========================================================================
// MARK: – SwiftUI-backed suggestion window

// ==========================================================================

extension MentionOverlayController {
    /// Borderless floating window that hosts a SwiftUI `MentionSuggestionListView`
    /// via `NSHostingView`, rendered on top of an `NSVisualEffectView` for the
    /// system vibrancy / popover material.
    final class SuggestionWindow: NSWindow {
        weak var parentTextView: MentionTextView?
        let placement: MentionOverlayController.Placement

        // SwiftUI bridge
        private let model = MentionSuggestionListModel()
        private var hostingView: NSHostingView<MentionSuggestionListView>?

        // MARK: – Init

        private var visibleRowLimit: Int

        init(
            parent: MentionTextView?,
            placement: MentionOverlayController.Placement,
            width: CGFloat = 240,
            visibleRowLimit: Int = 5
        ) {
            parentTextView = parent
            self.placement = placement
            self.visibleRowLimit = MentionOverlayController.normalizedVisibleRowLimit(visibleRowLimit)
            let rect = NSRect(x: 0, y: 0, width: width, height: 1)
            super.init(
                contentRect: rect,
                styleMask: .borderless,
                backing: .buffered,
                defer: true
            )

            isOpaque = false
            backgroundColor = .clear
            hasShadow = false
            level = .floating

            // Vibrancy background -----------------------------------------------
            let visualEffect = NSVisualEffectView(frame: rect)
            visualEffect.material = .popover
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 8
            visualEffect.layer?.masksToBounds = true
            visualEffect.layer?.borderWidth = 0.5
            visualEffect.layer?.borderColor = NSColor.separatorColor.cgColor

            // SwiftUI content ---------------------------------------------------
            model.visibleRowLimit = self.visibleRowLimit
            let listView = MentionSuggestionListView(model: model)
            let hosting = NSHostingView(rootView: listView)
            hosting.frame = visualEffect.bounds
            hosting.autoresizingMask = [.width, .height]

            // Ensure the hosting view is transparent so the vibrancy material
            // shines through behind the SwiftUI content.
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor

            visualEffect.addSubview(hosting)
            hostingView = hosting

            contentView = visualEffect

            // Wire up mouse click → highlight update
            model.onRowClicked = { [weak self] index in
                guard let self else { return }
                model.highlightedIndex = index
            }
        }

        // MARK: – Public helpers

        func updateSuggestions(_ items: [MentionSuggestion], highlighted: Int) {
            let rowCountForSizing = max(items.count, 1)

            // Always re-apply sizing, even when model values are unchanged.
            // This avoids a 1px-tall popup when the first update contains an
            // empty result set (e.g. slash-command query with no matching skills).
            if model.suggestions != items || model.highlightedIndex != highlighted {
                model.suggestions = items
                model.highlightedIndex = highlighted
            }

            resizeWindow(for: rowCountForSizing)
        }

        func moveHighlight(delta: Int) {
            guard !model.suggestions.isEmpty else { return }
            model.highlightedIndex = (model.highlightedIndex + delta + model.suggestions.count)
                % model.suggestions.count
        }

        func setVisibleRowLimit(_ limit: Int) {
            visibleRowLimit = MentionOverlayController.normalizedVisibleRowLimit(limit)
            model.visibleRowLimit = visibleRowLimit
            resizeWindow(for: max(model.suggestions.count, 1))
        }

        // MARK: – Layout

        private func resizeWindow(for itemCount: Int) {
            let visibleRows = min(itemCount, visibleRowLimit)
            let rowH = FontScalePreset.current.rowHeight + 4
            // 4pt padding top/bottom inside the VStack, plus 2pt spacing per gap
            let spacing = max(CGFloat(visibleRows - 1), 0) * 2
            let height = 4 + CGFloat(visibleRows) * rowH + spacing + 4
            var f = frame

            if placement == .below {
                let topY = f.maxY
                f.size.height = height
                f.origin.y = topY - height
            } else {
                f.size.height = height
            }

            setFrame(f, display: true)
        }
    }
}
