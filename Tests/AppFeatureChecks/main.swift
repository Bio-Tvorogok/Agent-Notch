import Foundation
import NotchCore

// Verify the compiled module used by the app, rather than inspecting Swift source.
let tabs = CardContent.tabs(blocks: CardBlock.allCases).map(\.rawValue)
guard tabs.contains("prompts") else {
    fputs("FAIL: this build has no Prompts tab; do not replace the installed app with it.\n", stderr)
    exit(1)
}
print("OK app features: Prompts tab is present in the compiled module")
