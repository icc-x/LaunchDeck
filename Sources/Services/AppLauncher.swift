import AppKit
import Foundation
import os

struct AppLauncher {
    private let logger = Logger(subsystem: "com.icc.launchdeck", category: "Launch")

    func launch(_ app: AppItem, completion: @escaping @Sendable (String?) -> Void) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        logger.info("app.launch.request name=\(app.name, privacy: .public)")

        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, error in
            if let error {
                logger.error("app.launch.failed name=\(app.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                completion(error.localizedDescription)
                return
            }
            logger.info("app.launch.succeeded name=\(app.name, privacy: .public)")
            completion(nil)
        }
    }
}
