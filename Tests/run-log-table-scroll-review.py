"""Render and exercise production log rows/viewport against inert, invented contacts.
No AppState, database, station settings, credentials, network, or radio is started.
Pass --baseline to compare the committed pre-fix row with the same fixture.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
source = (root / 'YAAM/LogTableView.swift').read_text()
baseline = '--baseline' in sys.argv
if baseline:
    source = subprocess.check_output(['git', 'show', '5e6ce74:YAAM/LogTableView.swift'], cwd=root, text=True)
def section(start, end):
    return source[source.index(start):source.index(end, source.index(start))]
parts = [section('fileprivate enum LogTableLayout', '// MARK: - High Performance'),
         section('fileprivate enum LogTableDateHelpers', '// MARK: - Sent Email Detail Context'),
         section('struct GridInspectionContext:', 'struct MiniGridWorldMapView:'),
         source[source.index('struct EmailCellView:'):]]
text = 'import SwiftUI\nimport AppKit\n' + '\n'.join(parts)
text = text.replace('fileprivate ', '')
text = text.replace('        let w = columnWidths[header] ?? LogTableLayout.defaultColumnWidth(for: header)',
                    '        let _ = ScrollMetrics.shared.cellBuilds += 1\n        let w = columnWidths[header] ?? LogTableLayout.defaultColumnWidth(for: header)')
fixture = (root / 'Tests/LogTableScrollReview.swift').read_text()
fixture = fixture.replace('BASELINE_MODE', 'true' if baseline else 'false')
if baseline:
    fixture = fixture.replace('columnWindow: window,', '')
with tempfile.TemporaryDirectory(prefix='yaam-scroll-') as temp:
    temp = Path(temp)
    (temp / 'Rows.swift').write_text(text)
    (temp / 'Review.swift').write_text(fixture)
    subprocess.run(['swiftc', '-O', '-parse-as-library', str(temp/'Rows.swift'), str(temp/'Review.swift'),
                    str(root/'YAAM/PinnedLogColumns.swift'), str(root/'YAAM/LogTableColumnWindow.swift'),
                    str(root/'YAAM/LogTableScrollViewport.swift'), '-o', str(temp/'review')], check=True)
    subprocess.run([str(temp/'review'), str(out)], check=True)
