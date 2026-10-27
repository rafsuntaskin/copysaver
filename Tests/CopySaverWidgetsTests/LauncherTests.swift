import CopySaverWidgets
import CopySaverPlatform
import Testing

@Test func widgetLinksContainOnlyExactNavigationAndSeparateDevelopmentIdentity() {
    for destination in LauncherDestination.allCases {
        for development in [false, true] {
            let scheme = development ? "copysaver-dev" : "copysaver"
            let url = destination.url(development: development)
            #expect(url.absoluteString == "\(scheme)://\(destination.rawValue)")
            #expect(AppDestination(url: url, scheme: scheme) != nil)
            #expect(url.query == nil && url.fragment == nil && url.user == nil && url.password == nil)
        }
    }
}
