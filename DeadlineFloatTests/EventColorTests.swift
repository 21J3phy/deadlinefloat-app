import XCTest
@testable import DeadlineFloat

final class EventColorTests: XCTestCase {
    private let livePalette = GoogleColorsResponse(
        updated: "2026-01-01T00:00:00Z",
        calendar: ["16": GoogleColorDefinition(background: "#4986e7", foreground: "#1d1d1d")],
        event: ["11": GoogleColorDefinition(background: "#dc2127", foreground: "#1d1d1d")]
    )

    // MARK: - Precedence

    func testEventColorIdWinsAndIsTheColourGoogleCalendarShows() {
        let resolver = EventColorResolver(palette: livePalette)
        let entry = Fixture.calendarEntry(background: "#16a765")
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "11"   // Tomato: #dc2127 in the API, #D50000 in Google Calendar

        let resolution = resolver.resolve(event: event, calendarEntry: entry)
        XCTAssertEqual(resolution.color.hexString, "#D50000")
        XCTAssertEqual(resolution.source, .event)
    }

    func testCalendarColorIsUsedWhenTheEventHasNone() {
        let resolver = EventColorResolver(palette: livePalette)
        let entry = Fixture.calendarEntry(background: "#16a765")   // Basil, as the API reports it
        let resolution = resolver.resolve(event: Fixture.timedEvent(start: Date()), calendarEntry: entry)
        XCTAssertEqual(resolution.color.hexString, "#0B8043", "drawn as Google Calendar draws Basil")
        XCTAssertEqual(resolution.source, .calendar)
    }

    func testCalendarColorIdIsResolvedToTheColourGoogleCalendarShows() {
        let resolver = EventColorResolver(palette: livePalette)
        let entry = Fixture.calendarEntry(background: nil, colorId: "16")   // Blueberry
        let resolution = resolver.resolve(event: Fixture.timedEvent(start: Date()), calendarEntry: entry)
        XCTAssertEqual(resolution.color.hexString, "#3F51B5")
        XCTAssertEqual(resolution.source, .calendar)
    }

    func testACustomCalendarColourIsKeptExactly() {
        let resolver = EventColorResolver(palette: livePalette)
        let entry = Fixture.calendarEntry(background: "#123456", colorId: nil)
        let resolution = resolver.resolve(event: Fixture.timedEvent(start: Date()), calendarEntry: entry)
        XCTAssertEqual(resolution.color.hexString, "#123456")
    }

    func testEveryAPIPresetHasAGoogleCalendarColour() {
        for hex in Array(GooglePalette.apiCalendarBackgrounds.values) + Array(GooglePalette.apiEventBackgrounds.values) {
            XCTAssertNotNil(GooglePalette.displayColorByAPIHex[hex.lowercased()], hex)
        }
        XCTAssertEqual(GooglePalette.calendarBackgrounds.count, 24)
        XCTAssertEqual(GooglePalette.eventBackgrounds.count, 11)
    }

    func testFallsBackToTheBuiltInPaletteWhenOffline() {
        let resolver = EventColorResolver(palette: nil)
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "5"   // Banana
        let resolution = resolver.resolve(event: event, calendarEntry: Fixture.calendarEntry(background: nil))
        XCTAssertEqual(resolution.color.hexString, "#F6BF26")
        XCTAssertEqual(resolution.source, .event)
    }

    func testNeutralFallbackWhenNothingIsKnown() {
        let resolver = EventColorResolver(palette: nil)
        let entry = Fixture.calendarEntry(background: nil, colorId: nil)
        let resolution = resolver.resolve(event: Fixture.timedEvent(start: Date()), calendarEntry: entry)
        XCTAssertEqual(resolution.source, .fallback)
        XCTAssertEqual(resolution.color, GooglePalette.fallback)
    }

    func testAnIdOnlyTheLivePaletteKnowsIsTranslatedByHex() {
        let palette = GoogleColorsResponse(
            updated: nil,
            calendar: nil,
            event: ["99": GoogleColorDefinition(background: "#dc2127", foreground: "#1d1d1d")]
        )
        let resolver = EventColorResolver(palette: palette)
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "99"
        let resolution = resolver.resolve(event: event, calendarEntry: Fixture.calendarEntry(background: nil))
        XCTAssertEqual(resolution.color.hexString, "#D50000", "the API hex for Tomato becomes Google Calendar's Tomato")
        XCTAssertEqual(resolution.source, .event)
    }

    // MARK: - Palette refresh

    func testPaletteRefreshIsNotNeededForIdsTheBuiltInTablesKnow() {
        let resolver = EventColorResolver(palette: nil)
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "7"
        let entry = Fixture.calendarEntry(background: nil, colorId: "23")
        XCTAssertFalse(resolver.needsPaletteRefresh(events: [event], calendars: [entry]))
    }

    func testPaletteRefreshIsNeededForAnIdNobodyKnows() {
        let resolver = EventColorResolver(palette: livePalette)
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "42"
        XCTAssertTrue(resolver.needsPaletteRefresh(events: [event], calendars: []))
        let entry = Fixture.calendarEntry(background: nil, colorId: "77")
        XCTAssertTrue(resolver.needsPaletteRefresh(events: [], calendars: [entry]))
    }

    func testPaletteRefreshIsNotNeededWhenTheLivePaletteExplainsTheId() {
        let palette = GoogleColorsResponse(
            updated: nil,
            calendar: ["77": GoogleColorDefinition(background: "#123456", foreground: nil)],
            event: ["42": GoogleColorDefinition(background: "#654321", foreground: nil)]
        )
        let resolver = EventColorResolver(palette: palette)
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "42"
        let entry = Fixture.calendarEntry(background: nil, colorId: "77")
        XCTAssertFalse(resolver.needsPaletteRefresh(events: [event], calendars: [entry]))
    }

    // MARK: - Urgency must not change the colour

    func testUrgencyDoesNotAlterTheSubjectColour() {
        let entry = Fixture.calendarEntry(background: "#16a765")
        let builder = Fixture.builder()
        let now = Fixture.date(2026, 9, 2, 12)

        let overdue = builder.build(event: Fixture.timedEvent(id: "a", start: now.addingTimeInterval(-3600)), calendarEntry: entry)!
        let imminent = builder.build(event: Fixture.timedEvent(id: "b", start: now.addingTimeInterval(3600)), calendarEntry: entry)!
        let later = builder.build(event: Fixture.timedEvent(id: "c", start: now.addingTimeInterval(48 * 3600)), calendarEntry: entry)!

        XCTAssertEqual(overdue.color, imminent.color)
        XCTAssertEqual(imminent.color, later.color)
        XCTAssertEqual(overdue.color.hexString, "#0B8043")
        XCTAssertNotEqual(overdue.urgency(now: now), later.urgency(now: now))
    }
}

final class RGBColorTests: XCTestCase {
    func testHexParsing() {
        XCTAssertEqual(RGBColor(hex: "#FFFFFF"), .white)
        XCTAssertEqual(RGBColor(hex: "000000"), .black)
        XCTAssertEqual(RGBColor(hex: "#a4bdfc")?.hexString, "#A4BDFC")
        XCTAssertEqual(RGBColor(hex: "#f00"), RGBColor(hex: "#ff0000"))
        XCTAssertEqual(RGBColor(hex: "#a4bdfcff")?.hexString, "#A4BDFC")
    }

    func testHexParsingRejectsGarbage() {
        XCTAssertNil(RGBColor(hex: ""))
        XCTAssertNil(RGBColor(hex: "#zzzzzz"))
        XCTAssertNil(RGBColor(hex: "#12345"))
        XCTAssertNil(RGBColor(hex: "rgb(1,2,3)"))
    }

    func testRelativeLuminanceEndpoints() {
        XCTAssertEqual(RGBColor.white.relativeLuminance, 1.0, accuracy: 0.0001)
        XCTAssertEqual(RGBColor.black.relativeLuminance, 0.0, accuracy: 0.0001)
    }

    func testContrastRatioEndpoints() {
        XCTAssertEqual(RGBColor.white.contrastRatio(to: .black), 21, accuracy: 0.01)
        XCTAssertEqual(RGBColor.white.contrastRatio(to: .white), 1, accuracy: 0.01)
    }

    func testEveryGoogleCalendarColourParses() {
        let hexes = Array(GooglePalette.eventBackgrounds.values) + Array(GooglePalette.calendarBackgrounds.values)
        XCTAssertEqual(hexes.count, 35)
        for hex in hexes {
            XCTAssertNotNil(RGBColor(hex: hex), hex)
        }
    }

    func testMixingIsClampedAndOrdered() {
        XCTAssertEqual(RGBColor.black.mixed(with: .white, amount: 0), .black)
        XCTAssertEqual(RGBColor.black.mixed(with: .white, amount: 1), .white)
        XCTAssertEqual(RGBColor.black.mixed(with: .white, amount: 2), .white)
        XCTAssertEqual(RGBColor.black.lightened(by: 0.5).red, 0.5, accuracy: 0.0001)
    }
}
