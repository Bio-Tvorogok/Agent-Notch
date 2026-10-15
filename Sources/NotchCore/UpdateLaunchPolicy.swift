import Foundation

public enum UpdateLaunchPolicy {
    public static func shouldStart(arguments: [String]) -> Bool {
        !arguments.dropFirst().contains {
            $0.hasPrefix("--snapshot") || ["--fixture", "--install-hooks", "--uninstall-hooks"].contains($0)
        }
    }
}
