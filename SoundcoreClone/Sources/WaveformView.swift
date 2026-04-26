import SwiftUI

struct WaveformView: View {
    @State private var phase: CGFloat = 0
    var isRecording: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isRecording ? Color.red : Color.gray.opacity(0.5))
                    .frame(width: 4, height: isRecording ? height(for: index) : 8)
                    .animation(
                        isRecording 
                        ? .easeInOut(duration: 0.3).repeatForever().delay(Double(index) * 0.1)
                        : .easeInOut(duration: 0.3),
                        value: isRecording
                    )
            }
        }
        .onAppear {
            if isRecording { phase = 1 }
        }
        .onChange(of: isRecording) { _, newValue in
            phase = newValue ? 1 : 0
        }
    }
    
    private func height(for index: Int) -> CGFloat {
        // Randomize heights slightly for a "live" feel when recording
        return CGFloat.random(in: 12...32)
    }
}
