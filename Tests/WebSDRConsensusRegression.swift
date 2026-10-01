import Foundation

@main
struct WebSDRConsensusRegression {
    static func main() {
        let epoch = Date(timeIntervalSince1970: 1_700_000_010)
        func sample(_ id: String, _ receiver: String, _ slot: Int, _ text: String) -> WebSDRConsensusInput {
            .init(id: id, receiverID: receiver,
                  slotStart: epoch.addingTimeInterval(Double(slot * 15)), text: text)
        }
        let aligned = WebSDRConsensusBuilder.build([
            sample("a1", "a", 0, "K1AAA W1BBB -10"),
            sample("a2", "a", 1, "K1CCC W1DDD R-08"),
            sample("b1", "b", 1, "K1AAA W1BBB -10"),
            sample("b2", "b", 2, "K1CCC W1DDD R-08")
        ], primaryReceiverID: "a")
        precondition(aligned.count == 2)
        precondition(aligned.allSatisfy { $0.receiverIDs.count == 2 },
                     "Two distinct messages must align a receiver delayed by one slot")

        let repeated = WebSDRConsensusBuilder.build([
            sample("a3", "a", 0, "CQ K1AAA FN42"),
            sample("a4", "a", 2, "CQ K1AAA FN42"),
            sample("b3", "b", 1, "CQ K1AAA FN42")
        ], primaryReceiverID: "a")
        precondition(repeated.count == 3,
                     "A repeating CQ alone must not claim cross-receiver consensus")

        let equalRank = WebSDRConsensusBuilder.build([
            sample("z", "a", 0, "CQ Z9ZZZ ZZ99"),
            sample("a", "a", 0, "CQ A1AAA AA00")
        ], primaryReceiverID: "a")
        precondition(equalRank.map(\.text) == ["CQ A1AAA AA00", "CQ Z9ZZZ ZZ99"],
                     "Equal-cycle rows must have a stable order when another decode arrives")

        let rate = 12_000
        let weak: [Float] = (0..<(rate * 13)).map { i in
            0.01 * sin(2 * .pi * 1_000 * Float(i) / Float(rate))
        }
        let strong = weak.map { $0 * 4 }
        let weakDB = WebSDRSignalLevel.estimate(samples: weak, sampleRate: rate,
                                                 onsetSeconds: 0, frequencyHz: 1_000)!
        let strongDB = WebSDRSignalLevel.estimate(samples: strong, sampleRate: rate,
                                                   onsetSeconds: 0, frequencyHz: 1_000)!
        precondition(abs(strongDB - weakDB - 12.04) < 0.5,
                     "Four times the audio amplitude should raise dBFS by about 12 dB")
        print("WebSDR consensus and dBFS regression passed")
    }
}
