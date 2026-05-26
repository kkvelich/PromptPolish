import XCTest

final class StreamingResponseParserTests: XCTestCase {

    func testIgnoresNonDataLines() {
        let parser = StreamingResponseParser()
        XCTAssertNil(parser.handle(line: ""))
        XCTAssertNil(parser.handle(line: "event: ping"))
        XCTAssertNil(parser.handle(line: ": comment line"))
    }

    func testIgnoresMalformedDataLines() {
        let parser = StreamingResponseParser()
        XCTAssertNil(parser.handle(line: "data: not-json"))
        XCTAssertNil(parser.handle(line: "data: {\"type\":\"unknown_event\"}"))
        XCTAssertNil(parser.handle(line: "data: {}"))
    }

    func testMessageStartCapturesUsage() {
        let parser = StreamingResponseParser()
        let line = #"data: {"type":"message_start","message":{"id":"msg_1","usage":{"input_tokens":42,"cache_read_input_tokens":2400,"cache_creation_input_tokens":0,"output_tokens":3}}}"#
        XCTAssertNil(parser.handle(line: line))
        XCTAssertEqual(parser.inputTokens, 42)
        XCTAssertEqual(parser.cacheReadTokens, 2400)
        XCTAssertEqual(parser.cacheCreationTokens, 0)
        XCTAssertEqual(parser.outputTokens, 3)
    }

    func testContentBlockDeltaYieldsChunk() {
        let parser = StreamingResponseParser()
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        XCTAssertEqual(parser.handle(line: line), .chunk("Hello"))
        XCTAssertEqual(parser.accumulatedText, "Hello")
    }

    func testTextAccumulatesAcrossMultipleDeltas() {
        let parser = StreamingResponseParser()
        let lines = [
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" "}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"world"}}"#
        ]
        let events = lines.compactMap { parser.handle(line: $0) }
        XCTAssertEqual(events, [.chunk("Hello"), .chunk(" "), .chunk("world")])
        XCTAssertEqual(parser.accumulatedText, "Hello world")
    }

    func testNonTextDeltaIsIgnored() {
        let parser = StreamingResponseParser()
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{"}}"#
        XCTAssertNil(parser.handle(line: line))
        XCTAssertEqual(parser.accumulatedText, "")
    }

    func testMessageDeltaUpdatesOutputTokens() {
        let parser = StreamingResponseParser()
        _ = parser.handle(line: #"data: {"type":"message_start","message":{"usage":{"input_tokens":10,"output_tokens":1}}}"#)
        XCTAssertEqual(parser.outputTokens, 1)
        _ = parser.handle(line: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":127}}"#)
        XCTAssertEqual(parser.outputTokens, 127)
    }

    func testMessageStopProducesDoneEvent() {
        let parser = StreamingResponseParser()
        _ = parser.handle(line: #"data: {"type":"message_start","message":{"usage":{"input_tokens":42,"cache_read_input_tokens":2400,"output_tokens":0}}}"#)
        _ = parser.handle(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Polished output"}}"#)
        _ = parser.handle(line: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":50}}"#)

        guard case let .done(result)? = parser.handle(line: #"data: {"type":"message_stop"}"#) else {
            XCTFail("Expected .done event from message_stop")
            return
        }
        XCTAssertEqual(result.text, "Polished output")
        XCTAssertEqual(result.inputTokens, 42)
        XCTAssertEqual(result.cacheReadTokens, 2400)
        XCTAssertEqual(result.outputTokens, 50)
    }

    func testFullStreamEndToEnd() {
        let parser = StreamingResponseParser()
        let stream = [
            "event: message_start",
            #"data: {"type":"message_start","message":{"usage":{"input_tokens":30,"cache_read_input_tokens":2440,"cache_creation_input_tokens":0,"output_tokens":2}}}"#,
            "",
            "event: content_block_start",
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            "",
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Draft "}}"#,
            "",
            "event: ping",
            #"data: {"type":"ping"}"#,
            "",
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"an email."}}"#,
            "",
            "event: content_block_stop",
            #"data: {"type":"content_block_stop","index":0}"#,
            "",
            "event: message_delta",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":4}}"#,
            "",
            "event: message_stop",
            #"data: {"type":"message_stop"}"#
        ]

        let events = stream.compactMap { parser.handle(line: $0) }

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .chunk("Draft "))
        XCTAssertEqual(events[1], .chunk("an email."))

        guard case let .done(result) = events[2] else {
            XCTFail("Expected last event to be .done")
            return
        }
        XCTAssertEqual(result.text, "Draft an email.")
        XCTAssertEqual(result.inputTokens, 30)
        XCTAssertEqual(result.cacheReadTokens, 2440)
        XCTAssertEqual(result.outputTokens, 4)
    }

    func testTrimsWhitespaceFromFinalText() {
        let parser = StreamingResponseParser()
        _ = parser.handle(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\n  Hello\n"}}"#)
        guard case let .done(result)? = parser.handle(line: #"data: {"type":"message_stop"}"#) else {
            XCTFail("Expected .done event")
            return
        }
        XCTAssertEqual(result.text, "Hello")
    }
}
