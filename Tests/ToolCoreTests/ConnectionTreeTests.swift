import Foundation
import XCTest

@testable import ToolCore

final class ConnectionTreeTests: XCTestCase {
  func testGroupingPreservesEveryOriginalAndDatabaseAndPolicy() throws {
    var a = ConnectionProfile(kind: .mysql)
    a.host = "DB.EXAMPLE.INVALID"
    a.database = "a"
    a.username = "reader"
    a.environment = "测试"
    var b = a
    b.id = UUID()
    b.database = "b"
    b.tls = true
    var duplicate = a
    duplicate.id = UUID()
    duplicate.name = "another service"
    let source = [a, b, duplicate]
    let groups = ConnectionGroup.build(source)
    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups[0].profiles, source)
    XCTAssertEqual(groups[0].scopes.map(\.database), ["a", "b"])
    XCTAssertEqual(groups[0].scopes[0].profiles.count, 2)
    XCTAssertTrue(groups[0].hasPolicyVariants)
    XCTAssertNotEqual(a.credentialScope, b.credentialScope)
    XCTAssertEqual(a.credentialScope, duplicate.credentialScope)
    let data = try JSONEncoder().encode(groups)
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("password"))
    XCTAssertEqual(ConnectionGroup.build(source).first?.id, groups[0].id)
  }
  func testAccountPortEnvironmentKindAndESBasePathRemainSeparate() {
    var a = ConnectionProfile(kind: .mysql)
    a.database = "fixture"
    a.username = "reader"
    var b = a
    b.id = UUID()
    b.username = "Reader"
    var c = a
    c.id = UUID()
    c.port = 3307
    var d = a
    d.id = UUID()
    d.environment = "生产"
    var pg = a
    pg.id = UUID()
    pg.kind = .pg
    XCTAssertEqual(ConnectionGroup.build([a, b, c, d, pg]).count, 5)
    var es = ConnectionProfile(kind: .es)
    es.endpoint = "http://example.invalid:9200/search"
    var alternate = es
    alternate.id = UUID()
    alternate.endpoint = "http://EXAMPLE.INVALID:9200/search/"
    XCTAssertEqual(ConnectionGroup.build([es, alternate]).count, 1)
    alternate.endpoint = "http://example.invalid:9200/other"
    XCTAssertEqual(ConnectionGroup.build([es, alternate]).count, 2)
    es.endpoint = "https://example.invalid"
    XCTAssertEqual(ConnectionIdentity(es).port, 443)
  }
  func testPostgresDatabasesAndRedisDBsAreChildrenNotExtraConnections() {
    var pg = ConnectionProfile(kind: .pg)
    pg.database = "one"
    var pg2 = pg
    pg2.id = UUID()
    pg2.database = "two"
    var redis = ConnectionProfile(kind: .redis)
    var redis2 = redis
    redis2.id = UUID()
    redis2.database = "13"
    let groups = ConnectionGroup.build([pg, pg2, redis, redis2])
    XCTAssertEqual(groups.count, 2)
    XCTAssertEqual(groups[0].scopes.map(\.database), ["one", "two"])
    XCTAssertEqual(groups[1].scopes.map(\.database), ["0", "13"])
    redis.username = "other"
    XCTAssertEqual(ConnectionGroup.build([redis, redis2]).count, 2)
  }
}
