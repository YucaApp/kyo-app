import Foundation

/// Rewrites a web join link so it opens straight in the service's own app,
/// skipping the browser tab that only exists to bounce you there.
///
/// The link comes from a calendar invite, which anyone can send, so the app
/// link is built from scratch out of the few parts that are needed and checked,
/// never by editing the original in place.
public enum NativeMeetingLink {
    /// Nil when the link has no app form; open the web link instead.
    public static func url(for web: URL) -> URL? {
        guard let scheme = web.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = web.host?.lowercased(),
            let parts = URLComponents(url: web, resolvingAgainstBaseURL: false)
        else { return nil }
        // Decoded, so an escaped ".." cannot slip past the checks below.
        let path = web.pathComponents

        if isHost(host, "zoom.us") || isHost(host, "zoomgov.com") {
            // /j/<number> joins a meeting, /w/<number> a webinar.
            guard path.count >= 3, path[1] == "j" || path[1] == "w", isMeetingNumber(path[2])
            else { return nil }
            var native = URLComponents()
            native.scheme = "zoommtg"
            native.host = host
            native.path = "/join"
            // The passcode stays exactly as it was encoded, so it remains one value.
            let passcode = parts.percentEncodedQueryItems?.first { $0.name == "pwd" }
            native.percentEncodedQueryItems =
                [
                    URLQueryItem(name: "action", value: "join"),
                    URLQueryItem(name: "confno", value: path[2]),
                ] + (passcode.map { [$0] } ?? [])
            return native.url
        }

        if host == "teams.microsoft.com" {
            guard path.count >= 4, path[1] == "l", path[2] == "meetup-join",
                !path.contains(where: { $0 == "." || $0 == ".." })
            else { return nil }
            var native = URLComponents()
            native.scheme = "msteams"
            native.host = host
            native.percentEncodedPath = parts.percentEncodedPath
            native.percentEncodedQuery = parts.percentEncodedQuery
            return native.url
        }

        return nil
    }

    /// Plain digits only. `Character.isNumber` would also accept digits from
    /// other scripts, which are not meeting numbers and cannot go in a URL raw.
    private static func isMeetingNumber(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (0x30...0x39).contains($0) }
    }

    private static func isHost(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
