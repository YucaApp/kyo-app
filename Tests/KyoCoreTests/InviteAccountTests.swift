import Foundation
import Testing
@testable import KyoCore

@Suite struct InviteAccountTests {
    // MARK: Which address was invited

    @Test func takesTheAddressFromTheUsersGuestEntry() {
        #expect(
            InviteAccount.email(attendee: URL(string: "mailto:sam@work.example"), calendarAccount: "Google")
                == "sam@work.example")
    }

    @Test func decodesAnEscapedAddress() {
        #expect(
            InviteAccount.email(attendee: URL(string: "mailto:sam%2Bcal@work.example"), calendarAccount: nil)
                == "sam+cal@work.example")
    }

    @Test func fallsBackToACalendarAccountNamedByItsAddress() {
        #expect(InviteAccount.email(attendee: nil, calendarAccount: "Sam@Home.example") == "sam@home.example")
    }

    @Test func aGuestEntryThatIsNotAnAddressFallsBackToo() {
        #expect(
            InviteAccount.email(
                attendee: URL(string: "/principals/abc123/"), calendarAccount: "sam@home.example")
                == "sam@home.example")
    }

    @Test func nilWhenNothingNamesAnAddress() {
        #expect(InviteAccount.email(attendee: nil, calendarAccount: "iCloud") == nil)
        #expect(InviteAccount.email(attendee: nil, calendarAccount: nil) == nil)
    }

    // MARK: Links

    private func link(_ url: String, _ account: String?) -> String {
        InviteAccount.link(URL(string: url)!, for: account).absoluteString
    }

    @Test func meetLinkNamesTheAccount() {
        #expect(
            link("https://meet.google.com/abc-defg-hij", "sam@work.example")
                == "https://meet.google.com/abc-defg-hij?authuser=sam@work.example")
    }

    @Test func keepsOtherParametersAndReplacesAnOldAccount() {
        #expect(
            link("https://meet.google.com/abc-defg-hij?pli=1&authuser=0", "sam@work.example")
                == "https://meet.google.com/abc-defg-hij?pli=1&authuser=sam@work.example")
    }

    @Test func otherServicesAreLeftAlone() {
        #expect(link("https://zoom.us/j/123456789", "sam@work.example") == "https://zoom.us/j/123456789")
        #expect(
            link("https://notmeet.google.com.evil.example/x", "sam@work.example")
                == "https://notmeet.google.com.evil.example/x")
    }

    @Test func onlyAddsTheAccountToASecureMeetingLink() {
        // Never over plain http, to an odd port, or with credentials in the link.
        for url in [
            "http://meet.google.com/abc-defg-hij", "https://meet.google.com:8443/abc-defg-hij",
            "https://user:pw@meet.google.com/abc-defg-hij",
        ] {
            #expect(link(url, "sam@work.example") == url)
        }
    }

    @Test func onlyAddsTheAccountToMeetingPaths() {
        // Other pages on the same host, such as redirects, do not get the address.
        for url in [
            "https://meet.google.com/linkredirect?dest=https://evil.example/",
            "https://meet.google.com/", "https://meet.google.com/a/b/c",
        ] {
            #expect(link(url, "sam@work.example") == url)
        }
        #expect(
            link("https://meet.google.com/lookup/abc123", "sam@work.example")
                == "https://meet.google.com/lookup/abc123?authuser=sam@work.example")
    }

    @Test func unchangedWithoutAnAccount() {
        #expect(link("https://meet.google.com/abc-defg-hij", nil) == "https://meet.google.com/abc-defg-hij")
    }
}
