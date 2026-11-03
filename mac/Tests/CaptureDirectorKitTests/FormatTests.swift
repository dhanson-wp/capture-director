import Testing
@testable import CaptureDirectorKit

@Test func lengthReadsAsMinutesAndSeconds() {
    #expect(Format.length(0) == "0:00")
    #expect(Format.length(4.4) == "0:04")
    #expect(Format.length(24) == "0:24")
    #expect(Format.length(65) == "1:05")
    #expect(Format.length(599.6) == "10:00")
    #expect(Format.length(3723) == "1:02:03")
    #expect(Format.length(-3) == "0:00")
}
