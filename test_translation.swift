import Foundation
import Translation

@available(macOS 15.0, *)
func check() async {
    let avail = LanguageAvailability()
    let langs = await avail.supportedLanguages
    print("Supported languages: \(langs)")
}
let group = DispatchGroup()
group.enter()
Task {
    if #available(macOS 15.0, *) {
        await check()
    }
    group.leave()
}
group.wait()
