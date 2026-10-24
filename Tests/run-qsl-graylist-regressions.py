"""Run the real aggregation/store/roster with inert services and actual QSO confirmation methods."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parent.parent
app = (root / 'YAAM/AppState.swift').read_text()
confirmed = app[app.index('    private static func isConfirmedChar('):app.index('    var isLotwConfirmed:')]
sent_char = app[app.index('    private static func isSentChar('):app.index('    var isLotwSent:')]
sent = app[app.index('    var isAnyQSLSent:'):app.index('    /// Days waiting for QSL confirmation.')]
model = '''import Foundation
nonisolated struct QSORecordModel: Identifiable, Equatable, Sendable {
 let id: UUID
 var fields: [String: String]
 init(id: UUID = UUID(), fields: [String: String]) { self.id = id; self.fields = fields }
 subscript(_ key: String) -> String { fields[key] ?? "" }
''' + confirmed + sent_char + sent + '\n}\n'
messages = 'extension AppState {\n' + app[app.index('    func confirmationRequestMessage('):app.index('    private var emailHistoryURL:')] + '\n}\n'
names = ['QSOIdentity', 'QSLGraylist', 'QSLGraylistMail', 'QSLGraylistStore', 'LatestSnapshotWorker', 'DigitalCallRosterEngine',
         'AppStateQSLGraylist', 'LogSearchEngine']
flags = ['swiftc', '-parse-as-library', '-swift-version', '5', '-default-isolation', 'MainActor',
         '-enable-upcoming-feature', 'NonisolatedNonsendingByDefault',
         '-enable-upcoming-feature', 'InferIsolatedConformances']
with tempfile.TemporaryDirectory(prefix='yaam-graylist-') as temp:
    temp = Path(temp)
    (temp/'Model.swift').write_text(model)
    (temp/'Messages.swift').write_text(messages)
    sources = [str(temp/'Model.swift'), str(root/'Tests/Support/QSLGraylistFixtures.swift'),
               str(temp/'Messages.swift'), str(root/'YAAM/EmailHistoryEntry.swift'),
               *[str(root/'YAAM'/f'{name}.swift') for name in names]]
    subprocess.run(flags + sources + [str(root/'Tests/QSLGraylistRegression.swift'), '-o', str(temp/'regression')], check=True)
    subprocess.run([str(temp/'regression')], check=True)
    subprocess.run(flags + [str(root/'YAAM/OperatorDeskNavigation.swift'), str(root/'Tests/OperatorDeskNavigationRegression.swift'), '-o', str(temp/'navigation')], check=True)
    subprocess.run([str(temp/'navigation')], check=True)
    if len(sys.argv) > 1:
        out = Path(sys.argv[1]).resolve()
        out.mkdir(parents=True, exist_ok=True)
        view = (root/'YAAM/QSLGraylistView.swift').read_text()
        (temp/'View.swift').write_text('import SwiftUI\n' + view[view.index('// Separate content'):])
        subprocess.run(flags + sources + [str(temp/'View.swift'), str(root/'YAAM/QSLGraylistEmailView.swift'), str(root/'YAAM/ResizablePresentation.swift'), str(root/'Tests/QSLGraylistVisualReview.swift'), '-o', str(temp/'render')], check=True)
        subprocess.run([str(temp/'render'), str(out)], check=True)
