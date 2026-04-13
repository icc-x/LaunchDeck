import Foundation

struct AppLaunchClient: Sendable {
    let launch: @Sendable (AppItem, @escaping @Sendable (String?) -> Void) -> Void

    static let live = AppLaunchClient { app, completion in
        AppLauncher().launch(app, completion: completion)
    }

    static let noop = AppLaunchClient { _, completion in
        completion(nil)
    }
}
