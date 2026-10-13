import AppKit
import SwiftUI
import NotchCore

/// A hidden panel stays mounted in AppKit; onDisappear alone cannot stop its reads.
struct UsageVisibility: NSViewRepresentable {
    let usage: UsageModel
    let agent: Agent

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        usage.show(agent, isVisible: { [weak view] in
            guard let view, view.window?.isVisible == true else { return false }
            var ancestor = view.superview
            while let parent = ancestor {
                if parent.isHidden { return false }
                if let clip = parent as? NSClipView, !clip.visibleRect.contains(view.convert(CGPoint.zero, to: clip)) { return false }
                ancestor = parent.superview
            }
            return true
        })
    }
}
