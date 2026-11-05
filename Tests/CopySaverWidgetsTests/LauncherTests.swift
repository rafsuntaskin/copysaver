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

@Test func communityWidgetLinksCannotRouteIntoProtectedLibrary() {
    for destination in LauncherDestination.allCases {
        for development in [false, true] {
            let scheme = development ? "copysaver-community-dev" : "copysaver-community"
            let url = destination.url(development: development, community: true)
            #expect(url.absoluteString == "\(scheme)://\(destination.rawValue)")
            #expect(AppDestination(url: url, scheme: scheme) != nil)
            #expect(AppDestination(url: url, scheme: development ? "copysaver-dev" : "copysaver") == nil)
        }
    }
}
