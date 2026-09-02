import Foundation

func runExportRegressionTests() {
    print("🧪 Running LogExportEngine Multi-Format Regression Tests...")

    let mockRecords: [[String: String]] = [
        [
            "CALL": "W1AW",
            "QSO_DATE": "20260902",
            "TIME_ON": "123000",
            "BAND": "20m",
            "MODE": "SSB",
            "FREQ": "14.225",
            "RST_SENT": "59",
            "RST_RCVD": "59",
            "NAME": "Hiram",
            "QTH": "Newington, CT",
            "DXCC": "291",
            "STATE": "CT",
            "CONT": "NA",
            "GRIDSQUARE": "FN31pr"
        ],
        [
            "CALL": "DL1ABC",
            "QSO_DATE": "20260902",
            "TIME_ON": "124500",
            "BAND": "15m",
            "MODE": "CW",
            "FREQ": "21.025",
            "RST_SENT": "599",
            "RST_RCVD": "599",
            "NAME": "Hans",
            "QTH": "Munich",
            "DXCC": "230",
            "CONT": "EU",
            "GRIDSQUARE": "JN58td"
        ]
    ]

    // 1. Test JSON export
    let json = LogExportEngine.generateJSON(records: mockRecords)
    assert(json.contains("W1AW"), "JSON must contain W1AW")
    assert(json.contains("total_qsos"), "JSON must contain total_qsos")
    print("✅ JSON Export Test Passed")

    // 2. Test Cabrillo 3.0 export
    let cabrillo = LogExportEngine.generateCabrillo(records: mockRecords, options: CabrilloExportOptions(
        contestID: "CQ-WW-SSB",
        callsign: "EP2AES",
        categoryOperator: "SINGLE-OP",
        categoryPower: "HIGH"
    ))
    assert(cabrillo.contains("START-OF-LOG: 3.0"), "Cabrillo header missing")
    assert(cabrillo.contains("CALLSIGN: EP2AES"), "Cabrillo callsign missing")
    assert(cabrillo.contains("CONTEST: CQ-WW-SSB"), "Cabrillo contest ID missing")
    assert(cabrillo.contains("QSO:"), "Cabrillo QSO line missing")
    assert(cabrillo.contains("END-OF-LOG:"), "Cabrillo footer missing")
    print("✅ Cabrillo 3.0 Export Test Passed")

    // 3. Test HTML export
    let html = LogExportEngine.generateHTML(headers: ["CALL", "BAND", "MODE"], records: mockRecords, title: "Test Log", callsign: "EP2AES")
    assert(html.contains("<!DOCTYPE html>"), "HTML doctype missing")
    assert(html.contains("W1AW"), "HTML W1AW missing")
    assert(html.contains("DL1ABC"), "HTML DL1ABC missing")
    print("✅ HTML Report Export Test Passed")

    // 4. Test Text Summary export
    let text = LogExportEngine.generateTextSummary(records: mockRecords, callsign: "EP2AES", sourceName: "Master Log")
    assert(text.contains("YAAM LOGBOOK SUMMARY REPORT"), "Text summary header missing")
    assert(text.contains("BAND BREAKDOWN:"), "Band breakdown missing")
    assert(text.contains("W1AW"), "Text summary call missing")
    print("✅ Text Summary Export Test Passed")

    print("🎉 ALL LogExportEngine Tests PASSED 100%!")
}

runExportRegressionTests()
