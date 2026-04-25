import SwiftUI

struct LiveInputView: View {
    @ObservedObject var capture: LiveAudioCapture

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Key display - large and prominent
            Text(capture.currentKey)
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            // BPM display
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(capture.currentBPM)
                    .font(.system(size: 36, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))

                Text("BPM")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .offset(y: -6)
            }

            Spacer()

            // Capture status
            HStack {
                Circle()
                    .fill(capture.isCapturing ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(capture.isCapturing ? "Listening" : "Inactive")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
