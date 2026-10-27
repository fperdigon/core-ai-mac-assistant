// Experimental probe: transcribes an audio file with Apple's on-device recognizer.
import Foundation
import Speech

setvbuf(stdout, nil, _IONBF, 0)
let arguments = CommandLine.arguments
guard arguments.count >= 3 else { print("usage: transcribe <locale> <file>"); exit(2) }
let locale = Locale(identifier: arguments[1])
let file = URL(fileURLWithPath: arguments[2])
print("initial authorization:", SFSpeechRecognizer.authorizationStatus().rawValue, "(0 notDetermined, 1 denied, 2 restricted, 3 authorized)")
let recognizer = SFSpeechRecognizer(locale: locale)
print("recognizer:", recognizer != nil, "onDevice:", recognizer?.supportsOnDeviceRecognition ?? false, "available:", recognizer?.isAvailable ?? false)
let done = DispatchSemaphore(value: 0)
SFSpeechRecognizer.requestAuthorization { status in
    print("authorization after request:", status.rawValue)
    guard status == .authorized, let recognizer, recognizer.supportsOnDeviceRecognition else { done.signal(); return }
    let request = SFSpeechURLRecognitionRequest(url: file)
    request.requiresOnDeviceRecognition = true
    recognizer.recognitionTask(with: request) { result, error in
        if let error { print("error:", error.localizedDescription); done.signal(); return }
        if let result, result.isFinal { print("TRANSCRIPT:", result.bestTranscription.formattedString); done.signal() }
    }
}
if done.wait(timeout: .now() + 60) == .timedOut { print("TIMEOUT waiting for authorization/recognition"); exit(3) }
