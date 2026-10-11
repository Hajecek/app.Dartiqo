import XCTest
@testable import Dartiqo

final class VoiceScoreParserTests: XCTestCase {
    func testSingleDartCzech() {
        XCTAssertEqual(VoiceScoreParser.parse("trojitá dvacet", mode: .darts), .darts([Dart(20, 3)]))
        XCTAssertEqual(VoiceScoreParser.parse("dvojitá šestnáct", mode: .darts), .darts([Dart(16, 2)]))
        XCTAssertEqual(VoiceScoreParser.parse("dvacet", mode: .darts), .darts([Dart(20)]))
        XCTAssertEqual(VoiceScoreParser.parse("bull", mode: .darts), .darts([Dart(25, 2)]))
        XCTAssertEqual(VoiceScoreParser.parse("mimo", mode: .darts), .darts([.miss]))
        XCTAssertEqual(VoiceScoreParser.parse("T20", mode: .darts), .darts([Dart(20, 3)]))
        XCTAssertEqual(VoiceScoreParser.parse("d16", mode: .darts), .darts([Dart(16, 2)]))
    }

    func testDartSequence() {
        XCTAssertEqual(
            VoiceScoreParser.parse("t20 t20 t20", mode: .darts),
            .darts([Dart(20, 3), Dart(20, 3), Dart(20, 3)])
        )
        XCTAssertEqual(
            VoiceScoreParser.parse("dvacet a dvacet a pět", mode: .darts),
            .darts([Dart(20), Dart(20), Dart(5)])
        )
        XCTAssertEqual(
            VoiceScoreParser.parse("20 5 1", mode: .darts),
            .darts([Dart(20), Dart(5), Dart(1)])
        )
        XCTAssertEqual(
            VoiceScoreParser.parse("dvacet pět jedna", mode: .darts),
            .darts([Dart(20), Dart(5), Dart(1)])
        )
        XCTAssertEqual(
            VoiceScoreParser.parse("20 20 20", mode: .darts),
            .darts([Dart(20), Dart(20), Dart(20)])
        )
    }

    func testTotalsMode() {
        XCTAssertEqual(VoiceScoreParser.parse("sto osmdesát", mode: .total), .total(180))
        XCTAssertEqual(VoiceScoreParser.parse("sto čtyřicet", mode: .total), .total(140))
        XCTAssertEqual(VoiceScoreParser.parse("dvacet šest", mode: .total), .total(26))
        XCTAssertEqual(VoiceScoreParser.parse("180", mode: .total), .total(180))
        XCTAssertEqual(VoiceScoreParser.parse("šedesát", mode: .total), .total(60))
        XCTAssertEqual(VoiceScoreParser.parse("dvacet", mode: .total), .total(20))
        XCTAssertEqual(VoiceScoreParser.parse("100", mode: .total), .total(100))
        XCTAssertEqual(VoiceScoreParser.parse("45", mode: .total), .total(45))
        // V součtu se šipky nerozkládají.
        XCTAssertNil(VoiceScoreParser.parse("20 5 1", mode: .total))
        XCTAssertNil(VoiceScoreParser.parse("T20", mode: .total))
    }

    func testDartsModeIgnoresVisitTotals() {
        XCTAssertNil(VoiceScoreParser.parse("180", mode: .darts))
        XCTAssertNil(VoiceScoreParser.parse("sto osmdesát", mode: .darts))
        XCTAssertNil(VoiceScoreParser.parse("šedesát", mode: .darts))
        XCTAssertNil(VoiceScoreParser.parse("dvacet šest", mode: .darts))
    }

    func testBust() {
        XCTAssertEqual(VoiceScoreParser.parse("bust", mode: .darts), .bust)
        XCTAssertEqual(VoiceScoreParser.parse("přehoz", mode: .total), .bust)
    }

    func testPreferTotalCompat() {
        XCTAssertEqual(VoiceScoreParser.parse("dvacet", preferTotal: true), .total(20))
        XCTAssertEqual(VoiceScoreParser.parse("dvacet", preferTotal: false), .darts([Dart(20)]))
    }
}
