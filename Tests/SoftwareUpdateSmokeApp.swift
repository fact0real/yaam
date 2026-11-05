import SwiftUI
import Sparkle
@main struct SmokeApp: App {
 let controller = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:nil,userDriverDelegate:nil)
 var body: some Scene {
  WindowGroup("Disposable YAAM Updater Test") {
   VStack(spacing:20) {
    Text("Disposable updater fixture").font(.title)
    Text("Installed build: \(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "?")").font(.title2)
    Text("No logbook, credentials, station settings or radio code is loaded.").foregroundStyle(.secondary)
    Button("Check disposable fixture update") { controller.checkForUpdates(nil) }
   }.padding(35).frame(minWidth:600,minHeight:260).onAppear { controller.startUpdater() }
  }
 }
}
