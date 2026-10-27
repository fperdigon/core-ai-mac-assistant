// Copyright 2026 Francisco Perdigon Romero and contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import MacPocketKnifeCore
import Testing

@MainActor
private final class FakeSpeech: SpeechTranscribing {
    var onPartial: (@MainActor (String) -> Void)?
    var onError: (@MainActor (DictationFailure) -> Void)?
    var failure: DictationFailure?
    var text = ""
    var starts = 0
    var stops = 0
    var locale: Locale?
    var hold = false
    var holdFinish = false
    var finishFailure: DictationFailure?
    var finishContinuation: CheckedContinuation<Void, Never>?
    var continuation: CheckedContinuation<Void, Never>?

    func start(locale: Locale) async throws {
        starts += 1
        self.locale = locale
        if hold { await withCheckedContinuation { continuation = $0 } }
        if let failure { throw failure }
    }
    func stop() -> String { stops += 1; return text }
    func finish() async throws -> String {
        if holdFinish { await withCheckedContinuation { finishContinuation = $0 } }
        if let finishFailure { throw finishFailure }
        return stop()
    }
}

@MainActor
private final class FakePasteboard: PasteboardWriting {
    var writes: [String] = []
    func write(_ text: String) { writes.append(text) }
}

@MainActor
private final class DictationNotices: AlertNotifying {
    var notices: [Notice] = []
    func deliver(_ notice: Notice) async { notices.append(notice) }
}

@MainActor
private struct DictationFixture {
    let speech = FakeSpeech()
    let pasteboard = FakePasteboard()
    let scheduler = FakeKeepAwakeScheduler()
    let notices = DictationNotices()
    let controller: DictationController
    init() {
        controller = DictationController(speech: speech, pasteboard: pasteboard,
                                        scheduler: scheduler, notices: notices)
    }
    func settle() async { for _ in 0..<30 { await Task.yield() } }
    func start() async {
        controller.toggle(locale: Locale(identifier: "en-US"))
        await settle()
    }
}

@MainActor
struct DictationTests {
    @Test func copiesAndCancelsDeadline() async {
        let f = DictationFixture()
        var changes = 0
        f.controller.onChange = { changes += 1 }
        await f.start()
        #expect(f.controller.state == .recording)
        #expect(f.speech.locale?.identifier == "en-US")
        f.speech.onPartial?("hello world")
        #expect(f.controller.wordCount == 2)
        f.speech.text = "  hello world \n"
        f.controller.toggle(locale: .current)
        await f.settle()
        #expect(f.controller.state == .idle)
        #expect(f.pasteboard.writes == ["hello world"])
        #expect(f.notices.notices.last?.title == "Dictation copied to the clipboard")
        #expect(f.notices.notices.last?.body == "2 words. Paste with Command-V.")
        #expect(f.scheduler.pendingCount == 0)
        #expect(changes >= 4)
        f.scheduler.advance(by: 600, includingCancelled: true)
        #expect(f.pasteboard.writes.count == 1)
    }

    @Test func emptyDoesNotTouchClipboard() async {
        let f = DictationFixture()
        await f.start()
        f.speech.text = " \n "
        f.controller.toggle(locale: .current)
        await f.settle()
        #expect(f.pasteboard.writes.isEmpty)
        #expect(f.notices.notices.last?.title == "No speech detected")
    }

    @Test func secondToggleDuringStartupDiscardsAndIgnoresStaleCallbacks() async {
        let f = DictationFixture()
        f.speech.hold = true
        await f.start()
        #expect(f.controller.state == .starting)
        let partial = f.speech.onPartial
        let error = f.speech.onError
        f.controller.toggle(locale: .current)
        f.speech.continuation?.resume()
        await f.settle()
        partial?("stale")
        error?(.recognitionFailed)
        #expect(f.controller.state == .idle)
        #expect(f.controller.wordCount == 0)
        #expect(f.pasteboard.writes.isEmpty)
        #expect(f.notices.notices.isEmpty)
        #expect(f.scheduler.pendingCount == 0)
    }

    @Test(arguments: [DictationFailure.permissionDenied, .onDeviceUnavailable, .microphoneUnavailable, .recognitionFailed])
    func startFailureDoesNotCopyOrRetry(_ failure: DictationFailure) async {
        let f = DictationFixture()
        f.speech.failure = failure
        await f.start()
        await f.settle()
        #expect(f.controller.state == (failure == .onDeviceUnavailable ? .idle : .error))
        #expect(f.controller.lastError == failure.message)
        #expect(f.speech.starts == 1)
        #expect(f.pasteboard.writes.isEmpty)
        #expect(f.notices.notices.last?.body == failure.message)
        #expect(f.scheduler.pendingCount == 0)
        f.speech.failure = nil
        await f.start()
        #expect(f.controller.state == .recording)
        #expect(f.controller.lastError == nil)
        f.controller.discard()
    }

    @Test func recognitionErrorDiscards() async {
        let f = DictationFixture()
        await f.start()
        f.speech.text = "private words"
        f.speech.onError?(.recognitionFailed)
        await f.settle()
        #expect(f.controller.state == .error)
        #expect(f.speech.stops == 1)
        #expect(f.speech.onError == nil)
        #expect(f.pasteboard.writes.isEmpty)
        #expect(f.scheduler.pendingCount == 0)
        #expect(f.notices.notices.last?.title == "Dictation unavailable")
    }

    @Test func tenMinuteLimit() async {
        let f = DictationFixture()
        await f.start()
        f.speech.text = "time is up"
        f.scheduler.advance(by: 599)
        #expect(f.controller.state == .recording)
        f.scheduler.advance(by: 1)
        await f.settle()
        #expect(f.controller.state == .idle)
        #expect(f.pasteboard.writes == ["time is up"])
    }

    @Test func waitsForFinalTextAndIgnoresRepeatedStop() async {
        let f = DictationFixture()
        await f.start()
        f.speech.onPartial?("partial")
        f.speech.holdFinish = true
        f.controller.toggle(locale: .current)
        await f.settle()
        f.controller.toggle(locale: .current)
        #expect(f.pasteboard.writes.isEmpty)
        #expect(f.speech.starts == 1)
        f.speech.text = "the final text"
        f.speech.finishContinuation?.resume()
        await f.settle()
        #expect(f.pasteboard.writes == ["the final text"])
    }

    @Test func finalRecognitionFailureDiscards() async {
        let f = DictationFixture()
        await f.start()
        f.speech.text = "discard this"
        f.speech.finishFailure = .recognitionFailed
        f.controller.toggle(locale: .current)
        await f.settle()
        #expect(f.controller.state == .error)
        #expect(f.pasteboard.writes.isEmpty)
        #expect(f.notices.notices.last?.body == DictationFailure.recognitionFailed.message)
    }

    @Test func discardWhileFinalizingNeverCopies() async {
        let f = DictationFixture()
        await f.start()
        f.speech.holdFinish = true
        f.controller.toggle(locale: .current)
        await f.settle()
        f.controller.discard()
        f.speech.finishContinuation?.resume()
        await f.settle()
        #expect(f.controller.state == .idle)
        #expect(f.pasteboard.writes.isEmpty)
    }

    @Test func factoryAndDiscard() {
        let speech = FakeSpeech()
        let pasteboard = FakePasteboard()
        let controller = DictationController.make(speech: speech, pasteboard: pasteboard, notices: DictationNotices())
        controller.discard()
        #expect(controller.state == .idle)
        #expect(pasteboard.writes.isEmpty)
    }

    @Test func olderSettingsDecode() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "dictationHotkeyEnabled")
        object.removeValue(forKey: "dictationHotkeyKey")
        object.removeValue(forKey: "dictationLanguage")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.dictationHotkeyEnabled)
        #expect(decoded.dictationHotkeyKey == "T")
        #expect(decoded.dictationLanguage == nil)
    }

    @Test(arguments: [(" a ", "A"), ("Z", "Z"), ("", "T"), ("TT", "T"), ("1", "T"), ("é", "T")])
    func keyValidation(_ input: String, _ expected: String) throws {
        var settings = AppSettings()
        settings.dictationHotkeyKey = input
        settings.dictationHotkeyEnabled = false
        settings.dictationLanguage = "en-GB"
        let sanitized = settings.validated()
        #expect(sanitized.dictationHotkeyKey == expected)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(sanitized))
        #expect(decoded == sanitized)
    }
}

@Test @MainActor func dictationLanguageSettingsPersist() {
    let store = DictationSettingsStore()
    let model = SettingsModel(store: store, secrets: InMemorySecretStore(),
                              transport: FakeTelegramTransport(), clock: FakeTelegramClock())
    #expect(model.dictationLanguageSelection == "")
    model.dictationLanguageSelection = "en-GB"
    #expect(store.load().dictationLanguage == "en-GB")
    #expect(model.dictationLanguageSelection == "en-GB")
    model.dictationLanguageSelection = ""
    #expect(store.load().dictationLanguage == nil)
}

@MainActor
private final class DictationSettingsStore: SettingsStore {
    var settings = AppSettings()
    func load() -> AppSettings { settings }
    func save(_ settings: AppSettings) { self.settings = settings }
}
