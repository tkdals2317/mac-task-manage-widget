import XCTest
@testable import TaskWidgetCore

final class BitbucketRemoteTests: XCTestCase {
    func testForms() {
        for u in ["git@bitbucket.org:midas/mrs-cms.git", "https://user@bitbucket.org/midas/mrs-cms.git",
                  "ssh://git@bitbucket.org/midas/mrs-cms", "https://bitbucket.org/midas/mrs-cms/"] {
            let p = BitbucketRemote.parse(u)
            XCTAssertEqual(p?.workspace, "midas", u)
            XCTAssertEqual(p?.slug, "mrs-cms", u)
        }
    }
    func testNonBitbucket() {
        XCTAssertNil(BitbucketRemote.parse("git@github.com:a/b.git"))
        XCTAssertNil(BitbucketRemote.parse("https://notbitbucket.org/a/b.git"))
        XCTAssertNil(BitbucketRemote.parse("git@bitbucket.org:onlyone"))
        XCTAssertNil(BitbucketRemote.parse(""))
    }
}
