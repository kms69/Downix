import XCTest
@testable import DownloadManager

final class URLClassifierTests: XCTestCase {

    func testDirectFilesByExtension() {
        for s in ["https://example.com/a.zip", "https://example.com/a/b/app.DMG?x=1",
                  "https://cdn.example.com/video.mp4", "https://example.com/doc.pdf"] {
            XCTAssertEqual(URLClassifier.quickClassify(URL(string: s)!), .direct, s)
        }
    }

    func testManifestsAreStreaming() {
        XCTAssertEqual(URLClassifier.quickClassify(URL(string: "https://x.example.com/live/index.m3u8")!), .streaming)
        XCTAssertEqual(URLClassifier.quickClassify(URL(string: "https://x.example.com/v/manifest.mpd")!), .streaming)
    }

    func testStreamingSites() {
        for s in ["https://www.youtube.com/watch?v=abc", "https://youtu.be/abc",
                  "https://vimeo.com/123", "https://m.twitch.tv/foo", "https://x.com/u/status/1"] {
            XCTAssertEqual(URLClassifier.quickClassify(URL(string: s)!), .streaming, s)
        }
    }

    /// "dropbox.com" / "netflix.com" contain the text "x.com" but are not X.
    func testHostMatchingIsNotSubstringMatching() {
        for s in ["https://www.dropbox.com/s/abc", "https://www.netflix.com/title/1",
                  "https://example.com/redirect?to=youtube.com"] {
            XCTAssertEqual(VideoPlatform.detect(from: URL(string: s)!), .generic, s)
            XCTAssertNil(URLClassifier.quickClassify(URL(string: s)!), s)   // needs the server probe
        }
        XCTAssertEqual(VideoPlatform.detect(from: "youtube.com/watch?v=abc"), .youtube)   // no scheme
    }

    func testContentTypeDecision() {
        XCTAssertEqual(URLClassifier.kind(fromContentType: "text/html; charset=utf-8", disposition: nil), .streaming)
        XCTAssertEqual(URLClassifier.kind(fromContentType: "application/octet-stream", disposition: nil), .direct)
        XCTAssertEqual(URLClassifier.kind(fromContentType: "video/mp4", disposition: nil), .direct)
        XCTAssertEqual(URLClassifier.kind(fromContentType: "application/vnd.apple.mpegurl", disposition: nil), .streaming)
        XCTAssertEqual(URLClassifier.kind(fromContentType: "text/html", disposition: "attachment; filename=a.html"), .direct)
        XCTAssertEqual(URLClassifier.kind(fromContentType: nil, disposition: nil), .streaming)
    }
}
