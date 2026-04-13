import AppKit
import Foundation

struct AppLauncher {
    func launch(_ app: AppItem, completion: @escaping @Sendable (String?) -> Void) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, error in
            if let error {
                completion(error.localizedDescription)
                return
            }
            completion(nil)
        }
    }
}
