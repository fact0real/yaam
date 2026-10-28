import AppKit
import SwiftUI
import Combine

// Inert owner: renders the real view without starting services or touching a user's archive.
@MainActor final class QSLInboxEngine: ObservableObject {
    @Published var receivedCards: [QSLInboundItem] = []
    @Published var archiveError: String?
    var inboundItems:[QSLInboundItem] { receivedCards.filter{$0.status != .archived && $0.status != .rejected} }
    func archivePendingItems() async {}
    func setStatus(_ status:QSLInboundStatus,for id:UUID) async -> Bool {false}
}
@main struct QSLReceivedCardsVisualReview {
 @MainActor static func main() throws {
  _=NSApplication.shared
  let out=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  let owner=QSLInboxEngine()
  let rows=[QSLInboundItem(source:.email,filename:"card.pdf",fromAddress:"operator@example.org",subject:"Your QSL card for our contact",callsign:"ZZ1TEST",qsoDate:"20261024",qsoTime:"0559",band:"20M",mode:"FT8",status:.matched,matchConfidence:100),QSLInboundItem(source:.image,filename:"scan.jpg",fromAddress:"second@example.org",subject:"Original QSL card retained after matching",callsign:"ZZ2TEST",status:.archived),QSLInboundItem(source:.eqsl,filename:"notice",fromAddress:"example.org",subject:"New eQSL notification",callsign:"ZZ3TEST")]
  for dark in [false,true] {for width in [760.0,1100.0] {
   owner.receivedCards=rows
   try render(owner,name:"cards-\(dark)-\(Int(width))",width:width,height:500,dark:dark,out:out)
  }}
  owner.receivedCards=[]
  try render(owner,name:"empty",width:760,height:500,dark:false,out:out)
  owner.archiveError="The received-card archive could not be read. Existing files were preserved."
  try render(owner,name:"error",width:760,height:500,dark:true,out:out)
  print("Rendered actual Received Cards view at compact/normal widths, light/dark, empty and error states")
 }
 @MainActor static func render(_ owner:QSLInboxEngine,name:String,width:Double,height:Double,dark:Bool,out:URL)throws{
  let content=QSLReceivedCardsView(inbox:owner,onImport:{},onAttach:{_ in},onReview:{_ in},onOpenCard:{_ in})
  let appearance=NSAppearance(named:dark ? .darkAqua:.aqua)!
  NSApp.appearance=appearance
  let host=NSHostingView(rootView:content.background(Color(NSColor.windowBackgroundColor)).environment(\.colorScheme,dark ? .dark:.light));host.appearance=appearance
  let window=NSWindow(contentRect:CGRect(x:0,y:0,width:width,height:height),styleMask:[.borderless],backing:.buffered,defer:false);window.appearance=appearance;window.contentView=host;host.frame=CGRect(x:0,y:0,width:width,height:height);window.makeKeyAndOrderFront(nil)
  RunLoop.current.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded();window.display()
  let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name+".png"));window.orderOut(nil)
 }
}
