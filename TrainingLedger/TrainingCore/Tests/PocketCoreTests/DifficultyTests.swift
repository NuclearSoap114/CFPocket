import XCTest
@testable import PocketCore
final class DifficultyTests: XCTestCase {
  func testCurrentCFColorBoundaries() {
    let cases: [(Int, Int, UInt32)] = [(1,1199,0x808080),(1200,1399,0x008000),(1400,1599,0x03A89E),(1600,1899,0x0000FF),(1900,2099,0xAA00AA),(2100,2399,0xFF8C00),(2400,4000,0xFF0000)]
    for (lo,hi,color) in cases { XCTAssertEqual(DifficultyPalette.codeforces(lo),color); XCTAssertEqual(DifficultyPalette.codeforces(hi),color) }
    XCTAssertEqual(DifficultyPalette.codeforces(nil),0x808080)
  }
  func testCurrentLuoguSchemaIncludesCyanAndLevelEight() throws {
    let raw = Data(#"{"status":200,"template":"problem.show","data":{"problem":{"pid":"CF4A","name":"Fixture","difficulty":8}}}"#.utf8)
    XCTAssertEqual(try LuoguParser.problem(raw,pid:"CF4A").difficultyLabel,"NOI/NOI+/CTS")
    XCTAssertEqual(LuoguParser.difficulties[5],"提高")
    XCTAssertEqual(DifficultyPalette.luogu(5),0x13C2C2)
    XCTAssertEqual(DifficultyPalette.luogu(6),0x3498DB)
    XCTAssertEqual(DifficultyPalette.luogu(7),0x9D3DCF)
    XCTAssertEqual(DifficultyPalette.luogu(8),0x0E1D69)
  }
  func testCFMetadataKeepsTagsAndUnratedDistinctFromMissingProblem() throws {
    let data = Data(#"{"status":"OK","result":{"problems":[{"contestId":4,"index":"A","name":"Watermelon","rating":800,"tags":["brute force","math"]},{"contestId":921,"index":"01","name":"Fixture","tags":[]}],"problemStatistics":[]}}"#.utf8)
    let rows = try SourceParser.problemList(data)
    XCTAssertEqual(rows.first(where:{$0.id == "4A"})?.tags,["brute force","math"])
    XCTAssertEqual(rows.first(where:{$0.id == "4A"})?.rating,800)
    XCTAssertNotNil(rows.first(where:{$0.id == "921-01"}))
    XCTAssertNil(rows.first(where:{$0.id == "921-01"})?.rating)
    XCTAssertNil(rows.first(where:{$0.id == "1Z"}))
  }
  func testMalformedCFMetadataIsNotUnratedOrEmptyTags() {
    for fields in [#""rating":800"#, #""rating":-1,"tags":[]"#, #""tags":[12]"#] {
      let raw = "{\"status\":\"OK\",\"result\":{\"problems\":[{\"contestId\":4,\"index\":\"A\",\"name\":\"Watermelon\",\(fields)}]}}"
      XCTAssertThrowsError(try SourceParser.problemList(Data(raw.utf8)))
    }
  }

  func testCapturedOfficialCFMetadata() throws {
    guard let path = ProcessInfo.processInfo.environment["CFPOCKET_METADATA_FIXTURE"] else { throw XCTSkip("Set CFPOCKET_METADATA_FIXTURE to a captured public API response") }
    let rows = try SourceParser.problemList(Data(contentsOf: URL(fileURLWithPath: path)))
    XCTAssertGreaterThan(rows.count, 10000)
    XCTAssertEqual(rows.first(where: { $0.id == "4A" })?.rating, 800)
    XCTAssertEqual(rows.first(where: { $0.id == "4A" })?.tags, ["brute force", "math"])
    XCTAssertEqual(rows.first(where: { $0.id == "921-01" })?.rating, 3200)
  }

}
