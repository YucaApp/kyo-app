import Foundation

/// Getting a call to open as the account that was invited.
public enum InviteAccount {
    /// The address the user was invited as: their own entry in the guest list,
    /// else the calendar's account when that is named by its address.
    public static func email(attendee: URL?, calendarAccount: String?) -> String? {
        if let attendee, attendee.scheme?.lowercased() == "mailto" {
            let address = attendee.absoluteString.dropFirst("mailto:".count)
                .prefix { $0 != "?" }
            if let decoded = String(address).removingPercentEncoding, isAddress(decoded) {
                return decoded.lowercased()
            }
        }
        if let calendarAccount, isAddress(calendarAccount) {
            return calendarAccount.lowercased()
        }
        return nil
    }

    /// Adds the account to links that understand it. Google picks the
    /// signed-in account named by `authuser`; other services are left alone.
    public static func link(_ url: URL, for account: String?) -> URL {
        guard let account, !account.isEmpty, isMeetMeeting(url),
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        // A "+" in a query means a space, so it has to be escaped by hand.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let value = account.addingPercentEncoding(withAllowedCharacters: allowed) ?? account
        parts.percentEncodedQueryItems =
            (parts.percentEncodedQueryItems ?? []).filter { $0.name != "authuser" }
            + [URLQueryItem(name: "authuser", value: value)]
        return parts.url ?? url
    }

    /// A plain https link to a Meet meeting: its code, nickname or lookup id.
    /// Other pages on that host, redirects among them, never get the address.
    private static func isMeetMeeting(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "meet.google.com",
            url.port == nil, url.user == nil, url.password == nil
        else { return false }
        let path = url.pathComponents.filter { $0 != "/" }
        switch path.count {
        case 1: return path[0] != "linkredirect"
        case 2: return path[0] == "lookup"
        default: return false
        }
    }

    private static func isAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
            && !text.contains(" ")
    }
}
