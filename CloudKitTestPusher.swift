//
//  CloudKitTestPusher.swift
//  Outcast
//
//  Created by D.J. Jones on 5/8/25.
//


import SwiftUI
import CloudKit

struct CloudKitTestPusher: View {
    @State private var resultMessage = "No action yet."

    var body: some View {
        VStack(spacing: 20) {
            Text("Push Test Record")
                .font(.title2).bold()

            Button("Save Test Record to CloudKit") {
                saveTestRecord()
            }

            Text(resultMessage)
                .padding()
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    func saveTestRecord() {
        let record = CKRecord(recordType: "TestRecord")
        record["note"] = "This is a test from D.J." as CKRecordValue

        CKContainer(identifier: "iCloud.com.dj.Outcast").privateCloudDatabase.save(record) { savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    resultMessage = "❌ Failed to save: \(error.localizedDescription)"
                } else {
                    resultMessage = "✅ Successfully saved test record!"
                }
            }
        }
    }
}
