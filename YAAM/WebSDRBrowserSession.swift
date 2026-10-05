import AppKit
import Foundation
import WebKit

struct WebSDRRecording {
    let wav: Data
    let startedAt: Date
    let stoppedAt: Date
}

/// Controls a standard WebSDR page and reads its own in-browser WAV recorder.
/// The recorder's blob is transferred in memory; no Downloads-folder interaction is needed.
@MainActor
final class WebSDRBrowserSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var onStatus: ((String) -> Void)?
    var onRecording: ((WebSDRRecording) async -> Void)?
    var onAudio: (([Float], Date, Int) -> Void)?

    private var webView: WKWebView?
    private var window: NSWindow?
    private var recordingTask: Task<Void, Never>?
    private var active = false
    private var listening = false
    private var lastAudioAt: Date?
    private var latestTapID = 0

    func start(url: URL, listening: Bool) {
        stop()
        active = true
        self.listening = listening
        lastAudioAt = nil
        latestTapID = 0
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let audioGate = WKUserScript(source: """
            (() => {
              window.__yaamListen = false;
              window.__yaamGains = [];
              window.__yaamSetListening = value => {
                window.__yaamListen = !!value;
                window.__yaamGains.forEach(g => { g.gain.value = value ? 1 : 0; });
              };
              if (!window.AudioNode) return;
              const connect = AudioNode.prototype.connect;
              AudioNode.prototype.connect = function(destination, ...args) {
                if (destination instanceof AudioDestinationNode) {
                  if (!this.__yaamTapped && this.context.createScriptProcessor) {
                    this.__yaamTapped = true;
                    const context = this.context;
                    const tapID = window.__yaamNextTapID = (window.__yaamNextTapID || 0) + 1;
                    // A reconnect can create a new audio node while the old one
                    // remains alive. Keep one bridge tap per page.
                    if (window.__yaamActiveTap) {
                      window.__yaamActiveTap.onaudioprocess = null;
                      window.__yaamActiveTap.disconnect();
                    }
                    // Fewer bridge messages keep the main thread responsive on
                    // long sessions without changing the 12 kHz receive samples.
                    const tap = context.createScriptProcessor(8192, 1, 1);
                    window.__yaamActiveTap = tap;
                    const silent = context.createGain();
                    silent.gain.value = 0;
                    const pending = new Int16Array(12000);
                    let pendingCount = 0;
                    tap.onaudioprocess = event => {
                      if (window.__yaamActiveTap !== tap) return;
                      const input = event.inputBuffer.getChannelData(0);
                      const ratio = context.sampleRate / 12000;
                      const output = [];
                      let position = tap.__yaamPosition || 0;
                      while (position < input.length - 1) {
                        const index = Math.floor(position);
                        const fraction = position - index;
                        const left = index < 0 ? (tap.__yaamLastSample || 0) : input[index];
                        const right = input[index + 1];
                        output.push(left + (right - left) * fraction);
                        position += ratio;
                      }
                      tap.__yaamPosition = position - input.length;
                      tap.__yaamLastSample = input[input.length - 1];
                      for (let i = 0; i < output.length; i++) {
                        const value = output[i];
                        const pcm = Math.max(-32768, Math.min(32767, Math.round(value * 32767)));
                        pending[pendingCount++] = pcm;
                        if (pendingCount < pending.length) continue;
                        const bytes = new Uint8Array(pending.buffer);
                        let hasAudio = false;
                        for (let j = 0; j < pendingCount; j++) {
                          if (pending[j] !== 0) { hasAudio = true; break; }
                        }
                        if (hasAudio) {
                          let binary = '';
                          for (let j = 0; j < bytes.length; j++) binary += String.fromCharCode(bytes[j]);
                          window.webkit.messageHandlers.yaamAudio.postMessage({
                            pcm: btoa(binary), endedAt: Date.now(), tapID
                          });
                        }
                        pendingCount = 0;
                      }
                    };
                    connect.call(this, tap);
                    connect.call(tap, silent);
                    connect.call(silent, destination);
                  }
                  window.__yaamGains.forEach(g => g.disconnect());
                  window.__yaamGains.length = 0;
                  const gate = this.context.createGain();
                  gate.gain.value = window.__yaamListen ? 1 : 0;
                  window.__yaamGains.push(gate);
                  connect.call(this, gate, ...args);
                  connect.call(gate, destination);
                  return destination;
                }
                return connect.call(this, destination, ...args);
              };
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(audioGate)
        configuration.userContentController.add(self, name: "yaamAudio")
        let page = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480),
                             configuration: configuration)
        page.navigationDelegate = self
        // Keeping WebKit attached to a live window prevents background media suspension.
        let leftmostScreen = NSScreen.screens.min { $0.frame.minX < $1.frame.minX }
        let screenFrame = leftmostScreen?.frame ?? .zero
        let host = NSWindow(contentRect: NSRect(x: screenFrame.minX - 639, y: screenFrame.minY, width: 640, height: 480),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.alphaValue = 0.01
        host.contentView = page
        host.ignoresMouseEvents = true
        host.hasShadow = false
        host.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        host.orderFront(nil)
        window = host
        webView = page
        page.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: 20))
    }

    func setListening(_ enabled: Bool) {
        listening = enabled
        webView?.evaluateJavaScript("window.__yaamSetListening?.(\(enabled ? "true" : "false"))")
    }

    func stop() {
        active = false
        recordingTask?.cancel()
        recordingTask = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "yaamAudio")
        webView?.navigationDelegate = nil
        webView = nil
        window?.orderOut(nil)
        window = nil
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard active, message.name == "yaamAudio", onAudio != nil,
              let body = message.body as? [String: Any],
              let encoded = body["pcm"] as? String,
              let milliseconds = body["endedAt"] as? NSNumber,
              let tapID = body["tapID"] as? NSNumber,
              encoded.count <= 64_000, tapID.intValue >= latestTapID,
              let bytes = Data(base64Encoded: encoded),
              bytes.count <= 24_000 else { return }
        latestTapID = tapID.intValue
        let samples: [Float] = bytes.withUnsafeBytes { buffer in
            let count = buffer.count / 2
            return (0..<count).map { index in
                let raw = UInt16(buffer[index * 2]) | (UInt16(buffer[index * 2 + 1]) << 8)
                return Float(Int16(bitPattern: raw)) / 32_768
            }
        }
        guard !samples.isEmpty else { return }
        if samples.contains(where: { abs($0) > 0.000_1 }) { lastAudioAt = Date() }
        onAudio?(samples, Date(timeIntervalSince1970: milliseconds.doubleValue / 1_000), tapID.intValue)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard active, self.webView === webView else { return }
        latestTapID = 0
        if lastAudioAt != nil {
            lastAudioAt = nil
            onStatus?("Receiver audio interrupted; reconnecting…")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard active, self.webView === webView else { return }
        setListening(listening)
        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            await self?.recordContinuously(in: webView)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard active else { return }
        onStatus?("Could not open WebSDR: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard active else { return }
        onStatus?("WebSDR stopped loading: \(error.localizedDescription)")
    }

    private func recordContinuously(in page: WKWebView) async {
        do {
            // The URL supplies the FT8 dial frequency and USB mode. WebSDR's
            // setmf arguments are the lower and upper passband edges in kHz.
            try await page.evaluateJavaScript("""
                (() => {
                  if (typeof setmf === 'function') setmf('usb', 0.15, 3.0);
                  if (typeof iOS_audio_start === 'function') iOS_audio_start();
                  if (typeof chrome_audio_start === 'function') chrome_audio_start();
                  const autoplay = document.getElementById('autoplay-start');
                  if (autoplay) autoplay.click();
                })()
                """)
            // WebAudio carries silence during network underruns, preserving the
            // sample clock. Prefer that continuous stream over sparse site WAVs.
            for _ in 0..<24 {
                guard active && !Task.isCancelled else { return }
                if let lastAudioAt, Date().timeIntervalSince(lastAudioAt) < 1 {
                    onStatus?("Continuous WebSDR audio · FT8 USB · ~3 kHz")
                    while active && !Task.isCancelled {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        guard active && !Task.isCancelled else { return }
                        if Date().timeIntervalSince(self.lastAudioAt ?? .distantPast) > 8 {
                            onStatus?("Receiver audio interrupted; reconnecting…")
                            self.lastAudioAt = nil
                            page.reload()
                            return
                        }
                    }
                    return
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            let startMilliseconds = try await page.evaluateJavaScript("""
                (() => {
                  const button = document.getElementById('recbutton');
                  if (!button) return 0;
                  button.click();
                  return button.textContent.trim().toLowerCase() === 'stop' ? Date.now() : 0;
                })()
                """) as? NSNumber
            guard var recordingStart = startMilliseconds?.doubleValue, recordingStart > 0 else {
                onStatus?("This WebSDR did not start its audio recorder. Try another receiver.")
                return
            }
            onStatus?("WebSDR tuned to FT8 USB · recording audio automatically")
            while active && !Task.isCancelled {
                let remaining = max(0, recordingStart / 1_000 + 15 - Date().timeIntervalSince1970)
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                guard active && !Task.isCancelled else { break }
                let value = try await page.callAsyncJavaScript("""
                    const button = document.getElementById('recbutton');
                    if (!button || button.textContent.trim().toLowerCase() !== 'stop')
                        throw new Error('Recorder is no longer active');
                    const oldHref = document.querySelector('#reccontrol a[href^="blob:"]')?.href;
                    button.click();
                    const stoppedAt = Date.now();
                    let link = document.querySelector('#reccontrol a[href^="blob:"]');
                    for (let attempt = 0; attempt < 20 && (!link || link.href === oldHref); attempt++) {
                        await new Promise(resolve => setTimeout(resolve, 100));
                        link = document.querySelector('#reccontrol a[href^="blob:"]');
                    }
                    if (!link) throw new Error('WebSDR produced no WAV file');
                    const href = link.href;
                    const blob = await (await fetch(href)).blob();
                    button.click(); // Start the next segment before transferring this one.
                    if (button.textContent.trim().toLowerCase() !== 'stop')
                        throw new Error('Recorder did not restart');
                    const nextStartedAt = Date.now();
                    const dataURL = await new Promise((resolve, reject) => {
                        const reader = new FileReader();
                        reader.onload = () => resolve(reader.result);
                        reader.onerror = () => reject(reader.error);
                        reader.readAsDataURL(blob);
                    });
                    return {dataURL, stoppedAt, nextStartedAt};
                    """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
                guard let value,
                      let payload = value["dataURL"] as? String,
                      let separator = payload.firstIndex(of: ","),
                      let wav = Data(base64Encoded: String(payload[payload.index(after: separator)...])),
                      let stoppedAt = value["stoppedAt"] as? NSNumber,
                      let nextStartedAt = value["nextStartedAt"] as? NSNumber,
                      !wav.isEmpty else {
                    onStatus?("WebSDR recorder returned an empty audio segment.")
                    continue
                }
                await onRecording?(WebSDRRecording(
                    wav: wav,
                    startedAt: Date(timeIntervalSince1970: recordingStart / 1_000),
                    stoppedAt: Date(timeIntervalSince1970: stoppedAt.doubleValue / 1_000)))
                recordingStart = nextStartedAt.doubleValue
            }
        } catch is CancellationError {
            return
        } catch {
            guard active else { return }
            onStatus?("WebSDR recording failed: \(error.localizedDescription)")
        }
    }
}

enum WebSDRWAV {
    /// Standard WebSDR recording is 16-bit mono PCM (usually 8 kHz).
    nonisolated static func samples(at12kHz wav: Data) -> [Float] {
        let bytes = [UInt8](wav)
        guard bytes.count >= 44, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else { return [] }
        func u16(_ i: Int) -> Int { Int(bytes[i]) | (Int(bytes[i + 1]) << 8) }
        func u32(_ i: Int) -> Int {
            Int(bytes[i]) | (Int(bytes[i + 1]) << 8) |
            (Int(bytes[i + 2]) << 16) | (Int(bytes[i + 3]) << 24)
        }
        var cursor = 12
        var rate = 0
        var channels = 0
        var bits = 0
        var format = 0
        var audioRange: Range<Int>?
        while cursor + 8 <= bytes.count {
            let size = u32(cursor + 4)
            let begin = cursor + 8
            guard size >= 0, size <= bytes.count - begin else { break }
            let tag = String(bytes: bytes[cursor..<(cursor + 4)], encoding: .ascii)
            if tag == "fmt ", size >= 16 {
                format = u16(begin)
                channels = u16(begin + 2)
                rate = u32(begin + 4)
                bits = u16(begin + 14)
            } else if tag == "data" {
                audioRange = begin..<(begin + size)
            }
            cursor = begin + size + (size & 1)
        }
        guard format == 1, channels == 1, bits == 16, (8_000...48_000).contains(rate),
              let audioRange else { return [] }
        let count = audioRange.count / 2
        guard count > 0 else { return [] }
        let input: [Float] = (0..<count).map { index in
            let offset = audioRange.lowerBound + index * 2
            let sample = Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
            return Float(sample) / 32_768
        }
        if rate == 12_000 { return input }
        let outputCount = Int((Double(count) * 12_000 / Double(rate)).rounded())
        return (0..<outputCount).map { index in
            let position = Double(index) * Double(rate) / 12_000
            let left = min(count - 1, Int(position))
            let right = min(count - 1, left + 1)
            let fraction = Float(position - Double(left))
            return input[left] + (input[right] - input[left]) * fraction
        }
    }
}
