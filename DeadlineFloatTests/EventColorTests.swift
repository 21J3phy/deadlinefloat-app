import XCTest
@testable import DeadlineFloat

final class EventColorTests: XCTestCase {
    private let livePalette = GoogleColorsResponse(
        updated: "2026-01-01T00:00:00Z",
        calendar: ["16": GoogleColorDefinition(background: "#4986e7", foreground: "#1d1d1d")],
        event: ["11": GoogleColorDefinition(background: "#dc2127", foreground: "#1d1d1d")]
    )

    // MARK: - Precedence

    func testEventColorIdWins() {
        let resolver = EventColorResolver(palette: livePalette)
        let entry = Fixture.calendarEntry(background: "#16a765")
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "11"

        let resolution = resolver.resolve(event: event, calendarEntry: entry)
        XCTAssertEqual(resolution.color.hexString, "#DC2127")
        XCTAssertEqual(resolution.source, .event)
    }

    func testCalendarColorIsUsedWhenTheEventHasNone() {
        let resolver = EventColorResolver(palette: livePalette)
        let entry = Fixture.calendarEntry(background: "#16a765")
        let resolution = resolver.resolve(event: Fixture.timedEvent(start: Date()), calendarEntry: entry)
        XCTAssertEqual(resolution.color.hexString, "#16A765")
        XCTAssertEqual(resolution.source, .calendar)
    }

    func testCalendarColorIdIsResolvedThroughThePalette() {
        let resolver = EventColorResolver(palette: livePalette)
        let entry = Fixture.calendarEntry(background: nil, colorId: "16")
        let resolution = resolver.resolve(event: Fixture.timedEvent(start: Date()), calendarEntry: entry)
        XCTAssertEqual(resolution.color.hexString, "#4986E7")
        XCTAssertEqual(resolution.source, .calendar)
    }

    func testFallsBackToGooglesPublishedPaletteWhenOffline() {
        let resolver = EventColorResolver(palette: nil)
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "5"   // Banana
        let resolution = resolver.resolve(event: event, calendarEntry: Fixture.calendarEntry(background: nil))
        XCTAssertEqual(resolution.color.hexString, "#FBD75B")
        XCTAssertEqual(resolution.source, .event)
    }

    func testNeutralFallbackWhenNothingIsKnown() {
        let resolver = EventColorResolver(palette: nil)
        let entry = Fixture.calendarEntry(background: nil, colorId: nil)
        let resolution = resolver.resolve(event: Fixture.timedEvent(start: Date()), calendarEntry: entry)
        XCTAssertEqual(resolution.source, .fallback)
        XCTAssertEqual(resolution.color, GooglePalette.fallback)
    }

    func testUnknownEventColorIdFallsBackToThePublishedPalette() {
        let resolver = EventColorResolver(palette: livePalette)
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "3"   // Grape, absent from the live palette above
        let resolution = resolver.resolve(event: event, calendarEntry: Fixture.calendarEntry(background: nil))
        XCTAssertEqual(resolution.color.hexString, "#DBADFF")
        XCTAssertEqual(resolution.source, .event)
    }

    // MARK: - Palette refresh

    func testPaletteRefreshIsNeededWhenThereIsNoPalette() {
        let resolver = EventColorResolver(palette: nil)
        XCTAssertTrue(resolver.needsPaletteRefresh(events: [], calendars: []))
    }

    func testPaletteRefreshIsNeededForAnUnseenEventColorId() {
        let resolver = EventColorResolver(palette: livePalette)
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "7"
        XCTAssertTrue(resolver.needsPaletteRefresh(events: [event], calendars: []))
    }

    func testPaletteRefreshIsNeededForAnUnseenCalendarColorId() {
        let resolver = EventColorResolver(palette: livePalette)
        let entry = Fixture.calendarEntry(background: nil, colorId: "23")
        XCTAssertTrue(resolver.needsPaletteRefresh(events: [], calendars: [entry]))
    }

    func testPaletteRefreshIsNotNeededWhenEverythingResolves() {
        let resolver = EventColorResolver(palette: livePalette)
        var event = Fixture.timedEvent(start: Date())
        event.colorId = "11"
        let entry = Fixture.calendarEntry(background: "#16a765", colorId: "99")
        XCTAssertFalse(
            resolver.needsPaletteRefresh(events: [event], calendars: [entry]),
            "an explicit backgroundColor means the calendar's colorId never has to be looked up"
        )
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
        XCTAssertEqual(overdue.color.hexString, "#16A765")
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

    func testContrastAdjustmentLeavesReadableColoursAlone() {
        let readable = RGBColor(hex: "#111111")!
        XCTAssertEqual(readable.adjustedForContrast(against: .lightSurface, minimumContrast: 4.5), readable)
    }

    func testContrastAdjustmentLiftsDarkColoursOnDarkBackgrounds() {
        let deepBlue = RGBColor(hex: "#1b2a80")!
        let adjusted = deepBlue.adjustedForContrast(against: .darkSurface, minimumContrast: 4.5)
        XCTAssertGreaterThanOrEqual(adjusted.contrastRatio(to: .darkSurface), 4.5)
        XCTAssertGreaterThan(adjusted.relativeLuminance, deepBlue.relativeLuminance)
    }

    func testContrastAdjustmentDarkensPaleColoursOnLightBackgrounds() {
        let paleYellow = RGBColor(hex: "#fbe983")!
        let adjusted = paleYellow.adjustedForContrast(against: .lightSurface, minimumContrast: 4.5)
        XCTAssertGreaterThanOrEqual(adjusted.contrastRatio(to: .lightSurface), 4.5)
        XCTAssertLessThan(adjusted.relativeLuminance, paleYellow.relativeLuminance)
    }

    func testEveryGoogleColourCanBeMadeReadableOnBothAppearances() {
        let hexes = Array(GooglePalette.eventBackgrounds.values) + Array(GooglePalette.calendarBackgrounds.values)
        XCTAssertEqual(hexes.count, 35)
        for hex in hexes {
            let color = RGBColor(hex: hex)
            XCTAssertNotNil(color, hex)
            for surface in [RGBColor.darkSurface, .lightSurface] {
                let adjusted = color!.adjustedForContrast(against: surface, minimumContrast: 4.5)
                XCTAssertGreaterThanOrEqual(
                    adjusted.contrastRatio(to: surface), 4.49,
                    "\(hex) is not readable on \(surface.hexString)"
                )
            }
        }
    }

    func testMixingIsClampedAndOrdered() {
        XCTAssertEqual(RGBColor.black.mixed(with: .white, amount: 0), .black)
        XCTAssertEqual(RGBColor.black.mixed(with: .white, amount: 1), .white)
        XCTAssertEqual(RGBColor.black.mixed(with: .white, amount: 2), .white)
        XCTAssertEqual(RGBColor.black.lightened(by: 0.5).red, 0.5, accuracy: 0.0001)
    }
}
