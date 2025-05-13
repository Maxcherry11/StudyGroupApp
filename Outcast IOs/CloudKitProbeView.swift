import SwiftUI
import CloudKit

struct CloudKitProbeView: View {
    @State private var statusMessage: String = "Checking iCloud status..."

    var body: some View {
        VStack(spacing: 20) {
            Text(statusMessage)
                .multilineTextAlignment(.center)
                .padding()

            Button("Check iCloud Status") {
                checkCloudKit()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .padding()
    }

    func checkCloudKit() {
        CKContainer.default().accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    statusMessage = "✅ iCloud is available."
                case .noAccount:
                    statusMessage = "🚫 No iCloud account found."
                case .restricted:
                    statusMessage = "🔒 iCloud access is restricted."
                case .couldNotDetermine:
                    statusMessage = "❓ Could not determine iCloud status."
                case .temporarilyUnavailable:
                    statusMessage = "⏳ iCloud is temporarily unavailable."
                @unknown default:
                    statusMessage = "⚠️ Received unknown iCloud status: \(status)"
                }
            }
        }
    }
}
