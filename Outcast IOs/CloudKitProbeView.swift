import SwiftUI
import CloudKit

struct CloudKitProbeView: View {
    @State private var statusMessage = "Checking iCloud status..."

    var body: some View {
        VStack(spacing: 20) {
            Text("CloudKit Probe Test")
                .font(.title2)
                .bold()

            Text(statusMessage)
                .multilineTextAlignment(.center)
                .padding()

            Button("Run Probe Again") {
                checkCloudKit()
            }
        }
        .onAppear(perform: checkCloudKit)
        .padding()
    }

    func checkCloudKit() {
        let container = CKContainer.default()
        container.accountStatus { status, error in
            DispatchQueue.main.async {
                if let error = error {
                    statusMessage = "❌ Error: \(error.localizedDescription)"
                    return
                }

                switch status {
                case .available:
                    statusMessage = "✅ iCloud is available."
                case .noAccount:
                    statusMessage = "❌ No iCloud account is signed in."
                case .restricted:
                    statusMessage = "❌ iCloud access is restricted."
                case .couldNotDetermine:
                    statusMessage = "❌ Could not determine iCloud status."
                @unknown default:
                    statusMessage = "❌ Unknown iCloud status."
                }
            }
        }
    }
}
