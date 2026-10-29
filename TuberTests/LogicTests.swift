import XCTest
@testable import Tuber

final class LogicTests: XCTestCase {
    func testVideoLinkFormats() {
        let id = "dQw4w9WgXcQ"
        let links = [
            "https://youtu.be/\(id)?si=abc",
            "https://www.youtube.com/watch?v=\(id)&t=42s",
            "https://youtube.com/shorts/\(id)",
            "https://m.youtube.com/watch?v=\(id)",
            "https://www.youtube.com/live/\(id)?feature=share",
        ]
        for link in links {
            XCTAssertEqual(VideoLink.videoID(from: URL(string: link)!), id, link)
        }
        XCTAssertNil(VideoLink.videoID(from: URL(string: "https://www.youtube.com/@veritasium")!))
        XCTAssertNil(VideoLink.videoID(from: URL(string: "https://example.com/watch?v=\(id)")!))
    }

    func testVideoIDValidation() {
        XCTAssertTrue(VideoLink.isValidID("dQw4w9WgXcQ"))
        XCTAssertTrue(VideoLink.isValidID("a-b_c123XYZ"))
        XCTAssertFalse(VideoLink.isValidID("x@evil.com/"))
        XCTAssertFalse(VideoLink.isValidID("../../aaaaa"))
        XCTAssertFalse(VideoLink.isValidID("short"))
        XCTAssertFalse(VideoLink.isValidID("dQw4w9WgXcQQ"))
    }

    func testRSSParse() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns="http://www.w3.org/2005/Atom">
          <title>Chan</title>
          <entry>
            <id>yt:video:AAAAAAAAAAA</id><yt:videoId>AAAAAAAAAAA</yt:videoId><yt:channelId>UC1</yt:channelId>
            <title>First &amp; best</title><published>2026-10-28T12:00:00+00:00</published>
          </entry>
          <entry>
            <id>yt:video:BBBBBBBBBBB</id><yt:videoId>BBBBBBBBBBB</yt:videoId><yt:channelId>UC1</yt:channelId>
            <title>Second</title><published>2026-10-27T12:00:00+00:00</published>
          </entry>
        </feed>
        """
        let result = try RSSParser.parse(Data(xml.utf8))
        XCTAssertEqual(result.channelTitle, "Chan")
        XCTAssertEqual(result.entries.map(\.id), ["AAAAAAAAAAA", "BBBBBBBBBBB"])
        XCTAssertEqual(result.entries[0].title, "First & best")
        XCTAssertEqual(result.entries[0].channelID, "UC1")
        XCTAssertEqual(result.entries[0].published, ISO8601DateFormatter().date(from: "2026-10-28T12:00:00Z"))
    }

    func testRSSMarksShorts() throws {
        let xml = """
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns="http://www.w3.org/2005/Atom">
          <title>Chan</title>
          <entry>
            <yt:videoId>AAAAAAAAAAA</yt:videoId><yt:channelId>UC1</yt:channelId><title>Video</title>
            <link rel="alternate" href="https://www.youtube.com/watch?v=AAAAAAAAAAA"/>
            <published>2026-10-28T12:00:00+00:00</published>
          </entry>
          <entry>
            <yt:videoId>BBBBBBBBBBB</yt:videoId><yt:channelId>UC1</yt:channelId><title>Short</title>
            <link rel="alternate" href="https://www.youtube.com/shorts/BBBBBBBBBBB"/>
            <published>2026-10-27T12:00:00+00:00</published>
          </entry>
        </feed>
        """
        let entries = try RSSParser.parse(Data(xml.utf8)).entries
        XCTAssertEqual(entries.map(\.isShort), [false, true])
    }

    func testRelativeDates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = 86_400.0
        XCTAssertEqual(ChannelVideos.relativeDate("5 days ago", now: now), now - 5 * day)
        XCTAssertEqual(ChannelVideos.relativeDate("1 month ago", now: now), now - 30 * day)
        XCTAssertEqual(ChannelVideos.relativeDate("Streamed 2 weeks ago", now: now), now - 14 * day)
        XCTAssertEqual(ChannelVideos.relativeDate("3 hours ago", now: now), now - 3 * 3600)
        XCTAssertEqual(ChannelVideos.relativeDate("2 years ago", now: now), now - 730 * day)
        XCTAssertNil(ChannelVideos.relativeDate("6.6M views", now: now))
    }

    func testChannelPageParse() {
        let json: [String: Any] = ["contents": ["richGridRenderer": ["contents": [
            ["richItemRenderer": ["content": ["lockupViewModel": [
                "contentId": "AAAAAAAAAAA", "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                "metadata": ["lockupMetadataViewModel": [
                    "title": ["content": "Hello"],
                    "metadata": ["contentMetadataViewModel": ["metadataRows": [["metadataParts": [
                        ["text": ["content": "1M views"]], ["text": ["content": "2 days ago"]]]]]]]]],
                "contentImage": ["thumbnailViewModel": ["overlays": [["thumbnailBottomOverlayViewModel": ["badges": [
                    ["thumbnailBadgeViewModel": ["text": "12:30"]]]]]]]]]]]],
            ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "NEXT"]]]],
        ]]]]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let page = ChannelVideos.parse(json, now: now)
        XCTAssertEqual(page.videos.map { $0.id }, ["AAAAAAAAAAA"])
        XCTAssertEqual(page.videos.first?.title, "Hello")
        XCTAssertEqual(page.videos.first?.duration, 750)
        XCTAssertEqual(page.videos.first?.published, now - 2 * 86_400)
        XCTAssertEqual(page.next, "NEXT")
    }

    func testTakeoutCSV() {
        let csv = """
        Channel Id,Channel Url,Channel Title
        UCHnyfMqiRRG1u-2MsSQLbXA,http://www.youtube.com/channel/UCHnyfMqiRRG1u-2MsSQLbXA,Veritasium
        UCsXVk37bltHxD1rDPwtNM8Q,http://www.youtube.com/channel/UCsXVk37bltHxD1rDPwtNM8Q,"Kurzgesagt – In a Nutshell, Inc"

        """
        let subs = SubscriptionsImport.parse(csv)
        XCTAssertEqual(subs.map { $0.id }, ["UCHnyfMqiRRG1u-2MsSQLbXA", "UCsXVk37bltHxD1rDPwtNM8Q"])
        XCTAssertEqual(subs.map { $0.title }, ["Veritasium", "Kurzgesagt – In a Nutshell, Inc"])
    }

    func testChannelList() {
        let text = """
        # my channels
        @veritasium
        https://www.youtube.com/@kurzgesagt/videos
        UCsXVk37bltHxD1rDPwtNM8Q
        - @mkbhd
        -https://youtube.com/channel/UCBJycsmduvYEL83R_U4JriQ

        not a channel
        """
        let items = SubscriptionsImport.parseList(text)
        XCTAssertEqual(items, [
            .init(ref: .handle("veritasium"), hidden: false),
            .init(ref: .handle("kurzgesagt"), hidden: false),
            .init(ref: .id("UCsXVk37bltHxD1rDPwtNM8Q"), hidden: false),
            .init(ref: .handle("mkbhd"), hidden: true),
            .init(ref: .id("UCBJycsmduvYEL83R_U4JriQ"), hidden: true),
        ])
    }

    private func seg(_ a: Double, _ b: Double) -> Segment { Segment(segment: [a, b], category: "sponsor") }

    func testSkipInside() {
        XCTAssertEqual(SkipLogic.skipTarget(at: 10, segments: [seg(5, 20)]), 20)
    }

    func testSkipChained() {
        XCTAssertEqual(SkipLogic.skipTarget(at: 10, segments: [seg(20.2, 30), seg(5, 20)]), 30)
    }

    func testNoSkipOutside() {
        XCTAssertNil(SkipLogic.skipTarget(at: 25, segments: [seg(5, 20)]))
    }

    func testWatched() {
        XCTAssertTrue(WatchRules.isWatched(position: 540, duration: 600))
        XCTAssertTrue(WatchRules.isWatched(position: 571, duration: 600))
        XCTAssertFalse(WatchRules.isWatched(position: 100, duration: 600))
        XCTAssertFalse(WatchRules.isWatched(position: 100, duration: nil))
    }
}
