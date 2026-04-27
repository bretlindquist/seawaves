import AVFoundation

let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: "/tmp/test.m4a"))
print(player != nil)
