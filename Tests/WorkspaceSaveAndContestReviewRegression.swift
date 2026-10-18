// The runner compiles the two unmodified production methods inside an isolated stand-in AppState.
// No real AppState initialization, database, credentials or uploads occur.
import Foundation

@main
@MainActor
struct WorkspaceSaveAndContestReviewRegression {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("yaam-workspace-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState()
        state.qsoRecords = [QSORecordModel(fields: ["CALL": "EA3XYZ", "EMAIL": "keep-local@example.invalid"])]
        state.loadedFileURL = folder // Writing a file over a directory must fail reliably.
        state.autoSaveActiveWorkspace()
        state.workspaceSaveQueue.sync {}
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(state.databaseStatus.contains("Automatic file save failed") && state.messages.count == 1)
        state.loadedFileURL = folder.appendingPathComponent("log.adi")
        state.qsoRecords[0].fields["RST_SENT"] = "57"
        state.autoSaveActiveWorkspace()
        state.qsoRecords[0].fields["RST_SENT"] = "59"
        state.autoSaveActiveWorkspace()
        state.workspaceSaveQueue.sync {}
        let saved = try String(contentsOf: state.loadedFileURL!, encoding: .utf8)
        let records = parseADIF(content: saved).1
        precondition(records.count == 1 && records[0]["RST_SENT"] == "59")
        precondition(records[0]["EMAIL"] == "keep-local@example.invalid", "Local file saves must retain personal fields")
        state.qsoRecords = []
        for invalid in ["", " ", "NaN", "Infinity", "-1", "abc", "7.100"] {
            do {
                _ = try state.logContestFastQSO(callsign: "EA3XYZ", band: "20M", mode: "CW", frequencyMHz: invalid,
                    rstSent: "", rstReceived: "", sentExchange: "", receivedExchange: "")
                preconditionFailure("A made-up/default/mismatched frequency was accepted")
            } catch QuickLogValidationError.invalidFrequency {}
            precondition(state.qsoRecords.isEmpty && state.currentContestSession?.nextSerial == 1)
            precondition(ZeroClickCloudUploadDaemon.shared.uploads == 0)
        }
        let logged = try state.logContestFastQSO(callsign: "EA3XYZ", band: "20M", mode: "CW", frequencyMHz: "14071",
            rstSent: "", rstReceived: "", sentExchange: "", receivedExchange: "")
        precondition(logged["FREQ"] == "14.071" && logged["RST_SENT"] == "599")
        precondition(state.qsoRecords.count == 1 && state.currentContestSession?.nextSerial == 2)
        precondition(ZeroClickCloudUploadDaemon.shared.uploads == 1)
        print("WorkspaceSaveAndContestReviewRegression passed: visible write errors, serial snapshots, full local fields, frequency admission before save/upload")
    }
}
