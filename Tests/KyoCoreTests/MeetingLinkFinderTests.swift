import Foundation
import Testing
@testable import KyoCore

@Suite struct MeetingLinkFinderTests {
    @Test func findsGoogleMeetInNotes() {
        let notes = "Agenda attached.\n\nJoin with Google Meet: https://meet.google.com/abc-defg-hij\nMore phone numbers: https://tel.meet/abc-defg-hij?pin=123"
        #expect(
            MeetingLinkFinder.find(url: nil, location: nil, notes: notes)?.absoluteString
                == "https://meet.google.com/abc-defg-hij")
    }

    @Test func findsZoomOnACompanySubdomainInLocation() {
        let location = "https://acme.zoom.us/j/91234567890?pwd=abcDEF"
        #expect(
            MeetingLinkFinder.find(url: nil, location: location, notes: nil)?.absoluteString
                == location)
    }

    @Test func findsTeamsInsideHTMLNotes() {
        let notes = #"<p>Hi</p><a href="https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=x">Join</a>"#
        #expect(
            MeetingLinkFinder.find(url: nil, location: nil, notes: notes)?.absoluteString
                == "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=x")
    }

    @Test func callLinkInNotesBeatsAnOrdinaryEventURL() {
        let found = MeetingLinkFinder.find(
            url: URL(string: "https://www.google.com/calendar/event?eid=xyz"),
            location: "Board room",
            notes: "https://meet.google.com/abc-defg-hij")
        #expect(found?.host == "meet.google.com")
    }

    @Test func fallsBackToTheEventURL() {
        let url = URL(string: "https://example.com/room/42")
        #expect(MeetingLinkFinder.find(url: url, location: nil, notes: nil) == url)
    }

    @Test func fallsBackToALinkInLocation() {
        #expect(
            MeetingLinkFinder.find(url: nil, location: "Online: https://example.com/room/42", notes: nil)?
                .absoluteString == "https://example.com/room/42")
    }

    @Test func ignoresUnrelatedLinksInNotes() {
        #expect(
            MeetingLinkFinder.find(url: nil, location: nil, notes: "Doc: https://docs.google.com/document/d/1")
                == nil)
    }

    @Test func ignoresNonWebEventURLs() {
        #expect(
            MeetingLinkFinder.find(url: URL(string: "message://%3Cabc%3E"), location: nil, notes: nil)
                == nil)
    }

    @Test func nilWhenThereIsNothing() {
        #expect(MeetingLinkFinder.find(url: nil, location: "Room 4", notes: "Bring laptop") == nil)
    }

    @Test func doesNotTreatLookalikeHostsAsZoom() {
        #expect(
            MeetingLinkFinder.find(url: nil, location: nil, notes: "https://notzoom.us/j/123") == nil)
    }

    // MARK: Hostile invites

    @Test func plainHTTPIsNeverOffered() {
        #expect(MeetingLinkFinder.find(url: nil, location: "http://evil.example/login", notes: nil) == nil)
        #expect(
            MeetingLinkFinder.find(url: URL(string: "http://evil.example/login"), location: nil, notes: nil)
                == nil)
        #expect(MeetingLinkFinder.find(url: nil, location: nil, notes: "http://meet.google.com/abc-defg-hij") == nil)
    }

    @Test func aBareSiteNameInTextIsNotALink() {
        #expect(MeetingLinkFinder.find(url: nil, location: "Meet at evil.com/login", notes: nil) == nil)
    }

    @Test func anUnacceptedInviteOnlyGetsLinksToCallServices() {
        #expect(
            MeetingLinkFinder.find(
                url: URL(string: "https://example.com/room/42"), location: "https://example.com/x",
                notes: nil, trusted: false) == nil)
        #expect(
            MeetingLinkFinder.find(
                url: nil, location: nil, notes: "https://meet.google.com/abc-defg-hij", trusted: false)?
                .host == "meet.google.com")
    }

    @Test func tellsCallServicesFromOtherSites() {
        #expect(MeetingLinkFinder.isCallService(URL(string: "https://meet.google.com/abc-defg-hij")!))
        #expect(MeetingLinkFinder.isCallService(URL(string: "https://acme.zoom.us/j/123")!))
        #expect(!MeetingLinkFinder.isCallService(URL(string: "https://example.com/room/42")!))
        #expect(!MeetingLinkFinder.isCallService(URL(string: "https://meet.google.com.evil.example/x")!))
    }

    @Test func namesTheSiteALinkLeadsTo() {
        #expect(MeetingLinkFinder.displayHost(URL(string: "https://www.example.com/room/42")!) == "example.com")
        #expect(MeetingLinkFinder.displayHost(URL(string: "https://Rooms.Example.com:8443/x")!) == "rooms.example.com")
        #expect(
            MeetingLinkFinder.displayHost(URL(string: "https://a-very-long-subdomain-name.of.some.example.com/x")!)
                == "…ain-name.of.some.example.com")
        // The owner of the site stays visible however long the front is.
        #expect(
            MeetingLinkFinder.displayHost(
                URL(string: "https://meet.google.com.aaaaaaaaaaaaaaaaaaaaaaaa.evil.example/x")!
            ).hasSuffix(".evil.example"))
    }
}

@Suite struct DeduplicationTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func meeting(_ id: String, _ title: String, offset: TimeInterval = 0, url: String? = nil) -> Meeting {
        Meeting(
            id: id, title: title, start: start.addingTimeInterval(offset),
            end: start.addingTimeInterval(offset + 1800), joinURL: url.flatMap(URL.init(string:)))
    }

    @Test func sameEventOnTwoCalendarsAppearsOnce() {
        // Copies of one event carry the same id whichever calendar they are read from.
        let merged = [meeting("uid-1", "Standup"), meeting("uid-1", "Standup")].deduplicated()
        #expect(merged.count == 1)
    }

    @Test func keepsTheCopyThatHasACallLink() {
        let merged = [
            meeting("uid-1", "Standup"), meeting("uid-1", "Standup", url: "https://meet.google.com/a"),
        ].deduplicated()
        #expect(merged.map(\.joinURL?.host) == ["meet.google.com"])
    }

    @Test func aLookalikeInviteIsNotMergedIntoTheRealMeeting() {
        // Same title and time, but a different event: someone else's invite.
        let real = meeting("uid-real", "Standup", url: "https://meet.google.com/a")
        let fake = meeting("uid-fake", "Standup", url: "https://evil.example/login")
        #expect([real, fake].deduplicated().map(\.id) == ["uid-real", "uid-fake"])
        #expect([fake, real].deduplicated().map(\.id) == ["uid-fake", "uid-real"])
        let bare = meeting("uid-real", "Standup")
        #expect([bare, fake].deduplicated().map(\.joinURL?.host) == [nil, "evil.example"])
    }

    @Test func sortsByStart() {
        let merged = [meeting("late", "B", offset: 600), meeting("early", "A")].deduplicated()
        #expect(merged.map(\.id) == ["early", "late"])
    }
}
