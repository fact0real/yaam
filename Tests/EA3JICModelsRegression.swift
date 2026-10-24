import Foundation
struct QSORecordModel {
    var fields:[String:String]
    var isConfirmed=false
    subscript(_ key:String)->String { fields[key] ?? "" }
}
struct QRZAwardSummary {
    let id:String, title:String, detail:String
    let percentComplete:Double
    let status:String
    let earned:Bool, progressAvailable:Bool
    let achievement:String, awardType:String, ribbonURL:String
}
@MainActor final class RoverModeEngine {
    static let shared=RoverModeEngine()
    func effectiveGrid(homeGrid:String)->String {homeGrid}
}
@main struct EA3JICModelsRegression {
    static func main() {
        let records=(3...5).map { zone in
            QSORecordModel(fields:["CALL":"K1ABC", "DXCC":"291", "COUNTRY":"United States", "CONT":"NA", "CQZ":String(zone), "FREQ":"14.074"], isConfirmed:zone==4)
        }
        let matrix=ClubLogDXCCMatrix.matrixFromLogbook(records:records)
        precondition(matrix.totalWorked==1 && matrix.cqZonesWorked==[3,4,5] && matrix.cqZonesConfirmed==[4])
        precondition(matrix.workedCount(band:"20m")==1)
        let antarctica=QSORecordModel(fields:["CALL":"DP0GVN", "DXCC":"13", "CONT":"AN", "BAND":"20M"],isConfirmed:true)
        precondition(ClubLogDXCCMatrix.matrixFromLogbook(records:[antarctica]).continentsConfirmed.isEmpty)
        for id in ["CQ-WW-SSB","CQ-WPX-CW","IARU-HF","CQ-160-CW"] {
            var session=ContestSession(contestID:id,operatorCallsign:"EA3JIC")
            session.startedAt = .distantPast
            let contact=QSORecordModel(fields:["CALL":"DL1ABC","CONT":"EU","BAND":"40M","MODE":"CW","QSO_DATE":"20261024","TIME_ON":"120000","CONTEST_ID":id])
            let europe=ContestWorkspaceLogic.summary(in:session,records:[contact])
            let asia=ContestWorkspaceLogic.summary(in:session,records:[contact],stationCallsign:"EP2AES")
            precondition(europe.totalPoints>0 && europe.totalPoints<asia.totalPoints, "The active operator's continent must change existing same-continent scoring")
            session.operatorCallsign=""
            let unknown=ContestWorkspaceLogic.summary(in:session,records:[contact])
            precondition(unknown.totalPoints==0 && !unknown.scoreNotice.isEmpty)
        }
        func entry(_ n:Int)->ContestCalendarEntry {
            .init(id:String(n),title:"Contest",utcWindow:"0000Z-2359Z",geographicFocus:"Worldwide",participation:"All",modes:"CW",bands:"HF",sourceURL:ContestCalendarService.weeklyURL.absoluteString)
        }
        let saved=(0..<10).map(entry)
        precondition(ContestCalendarService.replacementIssue(candidate:Array(saved.prefix(4)),previous:saved) != nil)
        precondition(ContestCalendarService.replacementIssue(candidate:saved,previous:saved)==nil)
        let missing=ContestCalendarEntry(id:"x",title:"Contest",utcWindow:"0000Z",geographicFocus:"Worldwide",participation:"All",modes:"Not specified",bands:"HF",sourceURL:"")
        precondition(ContestCalendarService.replacementIssue(candidate:[missing],previous:[]) != nil)
        print("Production models: per-QSO WAZ, inferred band, six-continent WAC, operator continent, unknown score and calendar replacement guards passed")
    }
}
