//
//  CloudKitDebugView.swift
//  Outcast
//
//  Created by D.J. Jones on 5/9/25.
//

import SwiftUI
import CloudKit

struct CloudKitDebugView: View {
    @State private var bundleID = Bundle.main.bundleIdentifier ?? "Unknown"
    @State private var accountStatus = "Checking..."
    @State private var containerID = "iCloud.com.dj.Outcast"
    @State private var testResult = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("📦 Bundle ID:")
                    .font(.headline)
                Text(bundleID)
                    .foregroundColor(.blue)

                Text("📂 Container:")
                    .font(.headline)
                Text(containerID)
                    .foregroundColor(.blue)

                Text("🗃️ iCloud Account Status:")
                    .font(.headline)
                Text(accountStatus)
                    .foregroundColor(accountStatus.contains("Available") ? .green : .red)

                Divider()

                Button("Try Save to CloudKit") {
                    saveTestRecord()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(testResult)
                    .padding()
                    .multilineTextAlignment(.center)
                    .foregroundColor(testResult.contains("succeeded") ? .green : .red)

                Spacer()
            }
            .padding()
            .navigationTitle("CloudKit Debug")
        }
        .onAppear {
            checkAccountStatus()
        }
    }

    private func checkAccountStatus() {
        CKContainer(identifier: containerID).accountStatus { status, error in
            DispatchQueue.main.async {
                if let error = error {
                    accountStatus = "Error: \(error.localizedDescription)"
                } else {
                    switch status {
                    case .available: accountStatus = "Available ✅"
                    case .noAccount: accountStatus = "No iCloud Account ❌"
                    case .restricted: accountStatus = "Restricted ⚠️"
                    case .couldNotDetermine: accountStatus = "Could Not Determine ❓"
                    @unknown default: accountStatus = "Unknown status 🚨"
                    }
                }
            }
        }
    }

    private func saveTestRecord() {
        let record = CKRecord(recordType: "DebugTest")
        record["message"] = "Test from CloudKitDebugView" as CKRecordValue

        CKContainer(identifier: containerID).publicCloudDatabase.save(record) { savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    testResult = "❌ Failed to save: \(error.localizedDescription)"
                } else {
                    testResult = "✅ Save succeeded!"
                }
            }
        }
    }
}

#Preview {
    CloudKitDebugView()
}
