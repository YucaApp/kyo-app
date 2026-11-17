import Foundation

/// Finds the link that joins a call, from the places calendars put it.
///
/// Everything here comes from an invite, which anyone can send. Only https
/// links written out in full are considered, and a link to an arbitrary site
/// is offered only for a meeting the user has accepted or made themselves.
public enum MeetingLinkFinder {
    /// `trusted` is false for an invitation the user has not accepted; then only
    /// links to known call services are offered, never an arbitrary site.
    public static func find(
        url: URL?, location: String?, notes: String?, trusted: Bool = true
    ) -> URL? {
        let eventURL = url.flatMap { isSecureWeb($0) ? $0 : nil }
        let fromLocation = links(in: location)
        let candidates = [eventURL].compactMap { $0 } + fromLocation + links(in: notes)

        // A link to a known call service wins wherever it sits.
        if let call = candidates.first(where: isCallService) { return call }
        // Otherwise only the URL and location fields count: notes are full of
        // unrelated links.
        guard trusted else { return nil }
        return eventURL ?? fromLocation.first
    }

    /// Whether the link goes to a known call service, as opposed to some other site.
    public static func isCallService(_ url: URL) -> Bool {
        guard isSecureWeb(url), let host = url.host?.lowercased() else { return false }
        return services.contains { service in
            (host == service.host || host.hasSuffix("." + service.host))
                && (service.paths.isEmpty || service.paths.contains { url.path.hasPrefix($0) })
        }
    }

    /// The site a link leads to, short enough for a button: "example.com".
    /// A long name loses its front, never its end: the end is who owns the site.
    public static func displayHost(_ url: URL) -> String {
        var host = (url.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let limit = 28
        return host.count > limit ? "…" + host.suffix(limit) : host
    }

    private struct Service {
        /// Matches the host itself and any subdomain of it.
        let host: String
        /// If set, the path must start with one of these.
        var paths: [String] = []
    }

    private static let services: [Service] = [
        Service(host: "meet.google.com"),
        Service(host: "zoom.us", paths: ["/j/", "/my/", "/w/", "/s/", "/wc/"]),
        Service(host: "zoomgov.com", paths: ["/j/", "/my/", "/w/", "/s/"]),
        Service(host: "teams.microsoft.com", paths: ["/l/meetup-join", "/meet/"]),
        Service(host: "teams.live.com", paths: ["/meet/"]),
        Service(host: "webex.com"),
        Service(host: "whereby.com"),
        Service(host: "meet.jit.si"),
        Service(host: "gotomeeting.com"),
        Service(host: "meet.goto.com"),
        Service(host: "chime.aws"),
        Service(host: "bluejeans.com"),
        Service(host: "around.co"),
        Service(host: "tuple.app"),
        Service(host: "riverside.fm"),
        Service(host: "facetime.apple.com", paths: ["/join"]),
        Service(host: "app.slack.com", paths: ["/huddle/"]),
        Service(host: "cal.com", paths: ["/video/"]),
        Service(host: "app.gather.town"),
        Service(host: "meet.livekit.io"),
    ]

    private static func isSecureWeb(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
    }

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func links(in text: String?) -> [URL] {
        guard let text, !text.isEmpty, let detector else { return [] }
        let whole = text as NSString
        return detector.matches(in: text, range: NSRange(location: 0, length: whole.length))
            .compactMap { match -> URL? in
                // The detector also turns a bare "example.com" into a link;
                // only one written out with its scheme counts.
                guard whole.substring(with: match.range).lowercased().hasPrefix("https://")
                else { return nil }
                return match.url
            }
            .filter(isSecureWeb)
    }
}
