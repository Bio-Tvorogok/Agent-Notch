import AppKit
import SwiftUI

/// Chips remain mounted while the list window is hidden, even when no rows exist.
struct UsageListVisibility: NSViewRepresentable {
    let usage: UsageModel
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        usage.listIsVisible = { [weak view] in view?.window?.isVisible == true }
    }
}
