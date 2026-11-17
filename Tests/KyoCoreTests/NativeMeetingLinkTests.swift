import Foundation
import Testing
@testable import KyoCore

@Suite struct NativeMeetingLinkTests {
    private func native(_ web: String) -> String? {
        NativeMeetingLink.url(for: URL(string: web)!)?.absoluteString
    }

    @Test func zoomJoinLinkCarriesMeetingNumberAndPasscode() {
        #expect(
            native("https://acme.zoom.us/j/91234567890?pwd=abcDEF.1")
                == "zoommtg://acme.zoom.us/join?action=join&confno=91234567890&pwd=abcDEF.1")
    }

    @Test func zoomJoinLinkWithoutPasscode() {
        #expect(native("https://zoom.us/j/123456789") == "zoommtg://zoom.us/join?action=join&confno=123456789")
    }

    @Test func zoomDropsTrackingParameters() {
        #expect(
            native("https://zoom.us/j/123456789?from=addon&pwd=x1")
                == "zoommtg://zoom.us/join?action=join&confno=123456789&pwd=x1")
    }

    @Test func zoomWebinarLink() {
        #expect(native("https://zoom.us/w/987654321") == "zoommtg://zoom.us/join?action=join&confno=987654321")
    }

    @Test func zoomPersonalLinkHasNoMeetingNumberSoStaysOnTheWeb() {
        #expect(native("https://zoom.us/my/sam") == nil)
    }

    @Test func teamsJoinLinkKeepsItsPathAndQueryExactly() {
        #expect(
            native("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%7d")
                == "msteams://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%7d")
    }

    @Test func servicesWithoutAnAppStayOnTheWeb() {
        #expect(native("https://meet.google.com/abc-defg-hij") == nil)
        #expect(native("https://example.com/room/42") == nil)
    }

    @Test func lookalikeHostsAreNotRewritten() {
        #expect(native("https://notzoom.us/j/123456789") == nil)
        #expect(native("https://teams.microsoft.com.evil.example/l/meetup-join/x") == nil)
    }

    // MARK: Hostile links (anyone can send an invite)

    @Test func nonLatinDigitsAreNotAMeetingNumber() {
        // These once crashed the app when the link was opened.
        #expect(native("https://zoom.us/j/%D9%A1%D9%A2%D9%A3") == nil)
        #expect(native("https://zoom.us/j/١٢٣") == nil)
    }

    @Test func zoomLinkIsRebuiltWithoutCredentialsPortOrFragment() {
        #expect(
            native("https://user:secret@acme.zoom.us:8443/j/123456789?pwd=abc#frag")
                == "zoommtg://acme.zoom.us/join?action=join&confno=123456789&pwd=abc")
    }

    @Test func zoomPasscodeCannotSmuggleInExtraParameters() {
        #expect(
            native("https://zoom.us/j/123456789?pwd=a%26action%3Dstart")
                == "zoommtg://zoom.us/join?action=join&confno=123456789&pwd=a%26action%3Dstart")
    }

    @Test func teamsLinkThatClimbsOutOfTheJoinPathIsNotRewritten() {
        #expect(
            native("https://teams.microsoft.com/l/meetup-join/../../l/chat/0/0?users=someone@evil.example")
                == nil)
        #expect(native("https://teams.microsoft.com/l/meetup-join/%2E%2E/chat") == nil)
    }

    @Test func teamsLinkDropsCredentialsPortAndFragment() {
        #expect(
            native("https://user:secret@teams.microsoft.com:8443/l/meetup-join/19%3ameeting/0?context=x#frag")
                == "msteams://teams.microsoft.com/l/meetup-join/19%3ameeting/0?context=x")
    }

    @Test func onlyWebLinksAreRewritten() {
        #expect(native("ftp://zoom.us/j/123456789") == nil)
    }
}
