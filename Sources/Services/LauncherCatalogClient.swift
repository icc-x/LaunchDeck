import Foundation

struct LauncherCatalogClient: Sendable {
    let loadApplications: @Sendable () -> [AppItem]
    let enrichApplications: @Sendable ([AppItem]) -> [AppItem]

    static let live = LauncherCatalogClient(
        loadApplications: {
            AppCatalogService().loadApplications()
        },
        enrichApplications: { apps in
            AppCatalogService().enrichApplications(apps)
        }
    )
}
