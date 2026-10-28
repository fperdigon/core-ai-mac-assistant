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

// Transcribes an audio file with Apple's on-device recognizer, the same engine and
// settings the app's dictation uses. It never falls back to server recognition.
// Exit codes: 0 ok, 2 usage, 3 timeout, 4 on-device unsupported, 5 not authorized, 6 error.
import Foundation
import Speech

setvbuf(stdout, nil, _IONBF, 0)
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: transcribe <locale> <audio file>")
    exit(2)
}
let locale = Locale(identifier: arguments[1])
let file = URL(fileURLWithPath: arguments[2])
let status = SFSpeechRecognizer.authorizationStatus()
print("authorization status:", status.rawValue, "(0 notDetermined, 1 denied, 2 restricted, 3 authorized)")
if status == .denied || status == .restricted { exit(5) }
guard let recognizer = SFSpeechRecognizer(locale: locale) else {
    print("no recognizer for", arguments[1])
    exit(4)
}
print("on-device supported:", recognizer.supportsOnDeviceRecognition, "available:", recognizer.isAvailable)
guard recognizer.supportsOnDeviceRecognition else { exit(4) }

let request = SFSpeechURLRecognitionRequest(url: file)
request.requiresOnDeviceRecognition = true
request.shouldReportPartialResults = true
let started = Date()
let task = recognizer.recognitionTask(with: request) { result, error in
    if let error {
        let nsError = error as NSError
        print("ERROR:", nsError.domain, nsError.code, error.localizedDescription)
        exit(6)
    }
    guard let result, result.isFinal else { return }
    print(String(format: "recognized in %.1fs", Date().timeIntervalSince(started)))
    print("TRANSCRIPT:", result.bestTranscription.formattedString)
    exit(0)
}
_ = task
// The recognizer reports on the main queue, so never block it: run the loop and time out from it.
DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
    print("TIMEOUT waiting for recognition")
    exit(3)
}
RunLoop.main.run()
