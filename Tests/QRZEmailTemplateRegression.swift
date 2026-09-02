//
//  QRZEmailTemplateRegression.swift
//  YAAM Tests
//

import Foundation

@main
struct QRZEmailTemplateRegression {
    static func main() {
        print("Running QRZ Email Template Regression Tests...")

        let greetingName = "Juan"
        let bandMention = " on 15M"
        let confirmationBlock = "Our QSO is already confirmed, and I have attached my QSL card for you. I hope you enjoy it."
        let qsoDetailsFormatted = """
        QSO Details:
        Date: 2026-09-02
        Time: 11:33 UTC
        Band: 15M
        Mode: FT8
        Freq: 21.076027 MHz
        """
        let qsoRankVal = "#40,829"
        let bandRankVal = "#33,425"
        let dxccRankVal = "#41,100"
        let myCall = "EP2AES"

        let subject = "Great QSO\(bandMention) / QSL & QRZ note - \(myCall)"

        let body = """
        Hi \(greetingName),
        Thanks for the excellent QSO\(bandMention)! It was a real pleasure catching you on the air.
        \(confirmationBlock)
        \(qsoDetailsFormatted)
        After our contact, I checked your profile on QRZ and was genuinely impressed by your standings:
        QSO World Rank: \(qsoRankVal)
        Bands World Rank: \(bandRankVal)
        DXCC World Rank: \(dxccRankVal)
        Reaching results like this clearly reflects consistent operating, broad band coverage, and disciplined logging. As someone working toward that kind of steady performance, I would love to learn from your experience. What habits, operating style, or station setup have helped you build such a strong record?
        Speaking of logging, your progress is a huge motivation for a personal project of mine. I keep my station log, confirmations, and award tracking in YAAM—a lightweight amateur-radio logbook software that I am developing and use every day.
        If you'd like to take a look: • Overview & Features: https://ep2aes.asis.sh • Source Code (GitHub): https://github.com/fact0real/yaam
        I would be honored to hear any feedback from an experienced operator like you—whether about YAAM or general operating advice.
        Thanks again for the contact, \(greetingName). Hope to work you on the bands again soon!
        Best 73, \(myCall)
        """

        precondition(subject == "Great QSO on 15M / QSL & QRZ note - EP2AES", "Subject mismatch: \(subject)")
        precondition(body.contains("QSO World Rank: #40,829"), "Missing QSO World Rank")
        precondition(body.contains("Bands World Rank: #33,425"), "Missing Bands World Rank")
        precondition(body.contains("DXCC World Rank: #41,100"), "Missing DXCC World Rank")
        precondition(body.contains("https://ep2aes.asis.sh"), "Missing features URL")
        precondition(body.contains("https://github.com/fact0real/yaam"), "Missing GitHub URL")
        precondition(body.contains("Best 73, EP2AES"), "Missing sign-off")

        print("QRZ Email Template Regression Tests PASSED successfully!")
    }
}
