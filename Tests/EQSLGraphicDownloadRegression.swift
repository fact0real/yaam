import AppKit
import Combine
import Foundation
struct QSORecordModel {let id=UUID();var fields:[String:String]}
@MainActor final class AppState {
 var activeStationProfileID:UUID?=UUID();var qsoRecords:[QSORecordModel]=[]
 func eqslConfirmationMatchIndex(_ record:[String:String],candidates:[[String:String]],claimed:inout Set<Int>)->Int?{nil}
 func autoSaveActiveWorkspace(){}
}
@MainActor final class QSLInboxEngine {
 static let shared=QSLInboxEngine();var receivedCards:[QSLInboundItem]=[]
 func receiveEQSLCard(record:[String:String],from:URL,profileID:UUID?,matchedQSOID:UUID?)async throws->URL{from}
}
func parseADIF(content:String)->(headers:[String],records:[[String:String]]) {([],[])}
final class GraphicFixtureProtocol:URLProtocol,@unchecked Sendable {
 static var requests:[URL]=[]
 static var image=Data()
 override class func canInit(with request:URLRequest)->Bool{true}
 override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
 override func startLoading(){
  let url=request.url!;Self.requests.append(url)
  let data=url.pathExtension=="jpg" ? Self.image:Data("<IMG SRC='../temporary/fixture.jpg'>".utf8)
  client?.urlProtocol(self,didReceive:HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading(){}
}
@main struct EQSLGraphicDownloadRegression {
 @MainActor static func main()async throws{
  _=NSApplication.shared
  let image=NSImage(size:NSSize(width:16,height:16));image.lockFocus();NSColor.blue.setFill();NSRect(x:0,y:0,width:16,height:16).fill();image.unlockFocus()
  GraphicFixtureProtocol.image=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.jpeg,properties:[:])!
  let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[GraphicFixtureProtocol.self]
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try?FileManager.default.removeItem(at:root)}
  let service=EQSLService(session:URLSession(configuration:config),storageDirectory:root,graphicRequestSpacing:0)
  let first=try await service.downloadCardImage(callsign:"ON5AM",date:"20260709",time:"165859",band:"17M",mode:"FT8",username:"TEST",password:"fixture")
  let params=Dictionary(URLComponents(url:GraphicFixtureProtocol.requests[0],resolvingAgainstBaseURL:false)!.queryItems!.map{($0.name,$0.value ?? "")},uniquingKeysWith:{$1})
  precondition(params["QSOMinute"]=="58" && params["QSOBand"]=="17M" && params["QSOMode"]=="FT8")
  let second=try await service.downloadCardImage(callsign:"ON5AM",date:"20260709",time:"170059",band:"17M",mode:"FT8",username:"TEST",password:"fixture")
  precondition(first != second && FileManager.default.fileExists(atPath:first.path))
  let count=GraphicFixtureProtocol.requests.count
  _=try await service.downloadCardImage(callsign:"ON5AM",date:"20260709",time:"165859",band:"17M",mode:"FT8",username:"TEST",password:"fixture")
  precondition(GraphicFixtureProtocol.requests.count==count)
  print("PASS: graphic parameters, seconds handled correctly, separate contacts retain separate cards, cache prevents repeated requests")
 }
}
