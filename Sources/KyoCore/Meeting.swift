import Foundation

/// A calendar event Kyo may remind about.
public struct Meeting: Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var joinURL: URL?
    /// All-day events show in the day's list but never alert.
    public var isAllDay: Bool
    /// The address the user was invited as, when the calendar says.
    public var account: String?
    /// An invitation the user has neither accepted nor declined.
    public var isUnanswered: Bool

    public init(
        id: String, title: String, start: Date, end: Date, joinURL: URL? = nil,
        isAllDay: Bool = false, account: String? = nil, isUnanswered: Bool = false
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.joinURL = joinURL
        self.isAllDay = isAllDay
        self.account = account
        self.isUnanswered = isUnanswered
    }
}

extension Array where Element == Meeting {
    /// Collapses the same event read from several calendars and sorts by start.
    ///
    /// Only copies with the same id merge. Matching on title and time would let
    /// a lookalike invite from someone else take the place of the real meeting.
    public func deduplicated() -> [Meeting] {
        var kept: [Meeting] = []
        var index: [String: Int] = [:]
        for meeting in self {
            if let existing = index[meeting.id] {
                if kept[existing].joinURL == nil, meeting.joinURL != nil {
                    kept[existing] = meeting
                }
            } else {
                index[meeting.id] = kept.count
                kept.append(meeting)
            }
        }
        // Stable, so same-time meetings keep the order the calendar gave them.
        return kept.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
    }
}
