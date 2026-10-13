import NotchCore

extension AppSettings {
    func displayedLimits(_ limits: VendorLimits) -> VendorLimits? {
        guard limits.vendor == .claude ? self.limits.claude : self.limits.codex,
              !self.limits.windows.isEmpty else { return nil }
        return UsageView.selectWindows(limits, short: self.limits.windows.contains(.short),
                                       weekly: self.limits.windows.contains(.weekly))
    }
}
