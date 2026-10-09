# Comprehensive User Manual for YAAM
### (Yet Another ADIF Manager — Native macOS Edition)

> **Welcome:** **YAAM** is a high-performance, native amateur radio logging and station automation suite engineered specifically for macOS (macOS 15+). It delivers local-first ADIF record management, direct transceiver network control, dedicated digital mode modems, a full CW training academy, shack clock telemetry, live weather radar, and tactical propagation HUD navigation within a unified, elegant macOS interface.

---

## Table of Contents
1. [Overview & Local-First Architecture](#1-overview--local-first-architecture)
2. [Digital Log Signing & Logbook of The World (LoTW) Submission](#2-digital-log-signing--logbook-of-the-world-lotw-submission)
   - [2.1 Cryptographic Signing and ARRL Certificates](#21-cryptographic-signing-and-arrl-certificates)
   - [2.2 In-Depth Guide to the Default Station Location Field](#22-in-depth-guide-to-the-default-station-location-field)
   - [2.3 Why Exact Case-Sensitive Matching with TQSL is Vital](#23-why-exact-case-sensitive-matching-with-tqsl-is-vital)
   - [2.4 macOS Sandbox Directory Synchronization (~/.tqsl)](#24-macos-sandbox-directory-synchronization-tqsl)
   - [2.5 Importing .p12 Container Certificates & Keychain Security](#25-importing-p12-container-certificates--keychain-security)
   - [2.6 Zero-Click Cloud Upload Background Daemon](#26-zero-click-cloud-upload-background-daemon)
   - [2.7 Bi-Directional Reconciliation in QSL Hub](#27-bi-directional-reconciliation-in-qsl-hub)
3. [CW Academy & Goertzel Audio Decoder](#3-cw-academy--goertzel-audio-decoder)
   - [3.1 40-Lesson Koch Method Training](#31-40-lesson-koch-method-training)
   - [3.2 Farnsworth Timing Mechanics](#32-farnsworth-timing-mechanics)
   - [3.3 Morse Echo Trainer](#33-morse-echo-trainer)
   - [3.4 Real-Time Goertzel DSP Audio Decoder](#34-real-time-goertzel-dsp-audio-decoder)
   - [3.5 K1EL WinKeyer Hardware Drivers & Serial Keying](#35-k1el-winkeyer-hardware-drivers--serial-keying)
   - [3.6 Comprehensive Q-Code and Contest Abbreviation Lexicon](#36-comprehensive-q-code-and-contest-abbreviation-lexicon)
4. [Shack HamClock & Remote Web Server](#4-shack-hamclock--remote-web-server)
   - [4.1 Multi-Pane Station Dashboard & Universal Coordinated Time (UTC)](#41-multi-pane-station-dashboard--universal-coordinated-time-utc)
   - [4.2 Live Solar & Geomagnetic Space Weather Indices (SFI, SSN, A-Index, Kp)](#42-live-solar--geomagnetic-space-weather-indices-sfi-ssn-a-index-kp)
   - [4.3 Real-Time NASA SDO Imagery & DRAP D-Region Absorption](#43-real-time-nasa-sdo-imagery--drap-d-region-absorption)
   - [4.4 Local Network Web Server for iPad, Tablets & Second Monitors](#44-local-network-web-server-for-ipad-tablets--second-monitors)
5. [Tactical Pilot HUD & HF Propagation Engine](#5-tactical-pilot-hud--hf-propagation-engine)
   - [5.1 VOACAP Point-to-Point Raytracing Engine](#51-voacap-point-to-point-raytracing-engine)
   - [5.2 Maximum Usable Frequency (MUF) & Signal-to-Noise (SNR) Metrics](#52-maximum-usable-frequency-muf--signal-to-noise-snr-metrics)
   - [5.3 Tactical Band Advisor](#53-tactical-band-advisor)
6. [Station Weather Radar & Lightning Safety Protocols](#6-station-weather-radar--lightning-safety-protocols)
   - [6.1 NEXRAD Doppler Precipitation Radar](#61-nexrad-doppler-precipitation-radar)
   - [6.2 Real-Time Cloud-to-Ground Lightning Discharge Tracking](#62-real-time-cloud-to-ground-lightning-discharge-tracking)
   - [6.3 Mast, Rotator & Equipment Safety Distance Rings](#63-mast-rotator--equipment-safety-distance-rings)
7. [Satellite Pass Tracking & High-Altitude APRS Balloons](#7-satellite-pass-tracking--high-altitude-aprs-balloons)
   - [7.1 Low-Earth Orbit Pass Predictions (AO-91, ISS, SO-50)](#71-low-earth-orbit-pass-predictions-ao-91-iss-so-50)
   - [7.2 Real-Time VHF/UHF Doppler Shift Correction](#72-real-time-vhfuhf-doppler-shift-correction)
   - [7.3 APRS High-Altitude Balloon Telemetry Tracking](#73-aprs-high-altitude-balloon-telemetry-tracking)
8. [Digital Contest Suite (FT8/FT4) & Master.scp Database](#8-digital-contest-suite-ft8ft4--masterscp-database)
   - [8.1 Official CQ WW Digi & ARRL Digi Workflows](#81-official-cq-ww-digi--arrl-digi-workflows)
   - [8.2 Bi-Directional UDP Stream with WSJT-X & JTDX](#82-bi-directional-udp-stream-with-wsjt-x--jtdx)
   - [8.3 Multiplier Matrix & Rate/Hour Speedometer](#83-multiplier-matrix--ratehour-speedometer)
   - [8.4 Pre-Submission Validation & Cabrillo 3.0 Generation](#84-pre-submission-validation--cabrillo-30-generation)
   - [8.5 Sub-Millisecond Master.scp Super Check Partial](#85-sub-millisecond-masterscp-super-check-partial)
9. [Operator Desk & Direct Icom MK2 LAN Architecture](#9-operator-desk--direct-icom-mk2-lan-architecture)
10. [Digital Call Roster with Speech Synthesis Alerts](#10-digital-call-roster-with-speech-synthesis-alerts)
11. [Logbook Table Modernization & Confirmation Credit Intelligence](#11-logbook-table-modernization--confirmation-credit-intelligence)
12. [Today's QSL Card Image Batch Dispatcher](#12-todays-qsl-card-image-batch-dispatcher)
13. [Tactical Rover Mode & Grid Scout](#13-tactical-rover-mode--grid-scout)
14. [Spectrum Bandmap & Waterfall Studio](#14-spectrum-bandmap--waterfall-studio)
15. [QSL Card Label Studio](#15-qsl-card-label-studio)
16. [International Club Memberships](#16-international-club-memberships)
17. [Club Log Live Spots & Band Intelligence Engine](#17-club-log-live-spots--band-intelligence-engine)
18. [Network-Attached Transceiver Emulator (NTE)](#18-network-attached-transceiver-emulator-nte)
19. [Super Check Partial (SCP) & Contest Exchange Predictor](#19-super-check-partial-scp--contest-exchange-predictor)
20. [Contest Bandmap HUD & Rapid Multiplier Navigation](#20-contest-bandmap-hud--rapid-multiplier-navigation)
21. [Contest Rate Speedometer & Multiplier 2D Matrix Dashboard](#21-contest-rate-speedometer--multiplier-2d-matrix-dashboard)
22. [Hardware Paddle Break-In & Instant Macro Interrupt Handler](#22-hardware-paddle-break-in--instant-macro-interrupt-handler)
23. [Lab599 Discovery TX-500: USB-C Integration (Digital & Morse Modes)](#23-lab599-discovery-tx-500-usb-c-integration-digital--morse-modes)
24. [Xiegu X6100: USB-C Integration (Digital & Morse Modes)](#24-xiegu-x6100-usb-c-integration-digital--morse-modes)
25. [Multi-Rig FT8 Cluster: Multi-Transceiver Operation (SO2R / SO3R)](#25-multi-rig-ft8-cluster-multi-transceiver-operation-so2r--so3r)

---

## 1. Overview & Local-First Architecture

YAAM is architected under the **Local-First** philosophy: all contact history, awards credits, station profiles, and security keys are stored locally on your Mac inside a high-concurrency **SQLite database with Write-Ahead Logging (WAL)**. 

### Core Resilience Characteristics:
* **Crash & Power-Failure Immune:** Transactions are atomic and journaled via WAL. Sudden macOS power losses or app terminations will never corrupt your logbook.
* **Automatic Restore Points:** YAAM creates a point-in-time snapshot backup before every major ADIF import, bulk cloud sync, or mass confirmation reconciliation.
* **Pure Native Performance:** Built with Swift and SwiftUI for zero lag, sub-millisecond search across 500,000+ QSOs, and low battery consumption on Apple Silicon MacBooks.

---

## 2. Digital Log Signing & Logbook of The World (LoTW) Submission

Direct integration with the American Radio Relay League (ARRL) **Logbook of The World (LoTW)** is one of YAAM’s most sophisticated modules, executing cryptographic signing through the official **TrustedQSL (`tqsl`)** engine.

### 2.1 Cryptographic Signing and ARRL Certificates
Unlike commercial sites like QRZ or Club Log which accept plain ADIF text over HTTP, LoTW enforces **Public Key Cryptography** to verify the authenticity of every radio contact and ensure the integrity of international awards (DXCC, WAS, VUCC).
The command-line `tqsl` binary packages contacts, signs them using your ARRL private certificate key, produces an encrypted `.tq8` payload, and transmits it directly to ARRL’s secure ingest endpoints.

### 2.2 In-Depth Guide to the Default Station Location Field
Located in `Settings > LoTW`, you will find:
```text
Default Station Location (e.g. Home):
```
This field is the linchpin of your digital signing workflow.

#### What is a "Station Location" in TQSL?
Your ARRL digital certificate (`.p12` / Call Certificate) validates only your identity and **Callsign**. It does not specify your physical location during a contact. In TQSL, a **Station Location** binds geographic parameters to that callsign:
* DXCC Entity (e.g. *Iran*, *United States*, *Germany*)
* Maidenhead Grid Square (e.g. `LL25wr` or `FN31pr`)
* CQ Zone (e.g. `21` or `05`)
* ITU Zone (e.g. `40` or `08`)
* State / County / Province / Administrative Subdivision

The custom name assigned to this location profile inside TQSL (such as `EP2AES-Home`, `Default`, or `Kish-Island`) is your **Station Location Name**.

### 2.3 Why Exact Case-Sensitive Matching with TQSL is Vital
When YAAM signs your contacts, it triggers `tqsl` under the hood:
```bash
tqsl -d -u -x -q -l "EP2AES-Home" -p "Password" /path/to/contacts.adi
```
The `-l` switch instructs `tqsl` which configuration record to query from its internal SQLite database (`station_data`).

> [!CAUTION]
> **Mandatory Character-for-Character Accuracy:**  
> The name entered into YAAM’s **Default Station Location** must match the name configured in the TQSL desktop application **exactly, including uppercase/lowercase letters, punctuation, and spacing**.  
> **Example:** If your TQSL location is named `EP2AES-Home`:
> * `ep2aes-home` ❌ (Fails with error)
> * `Home` ❌ (Fails with error)
> * `EP2AES-Home` ✅ (Succeeds immediately)  
> Any mismatch causes TQSL to halt immediately and report `Station location not found`.

#### Default vs. Profile-Specific Station Locations:
If you operate from multiple locations (e.g. Home, Mountain Portable, Island DXpedition), the value in `Settings > LoTW` serves as the global fallback. You can override it per profile in `Settings > Stations > Service Identity` under `LoTW station location`. YAAM dynamically selects the correct TQSL location name whenever you switch active station profiles.

### 2.4 macOS Sandbox Directory Synchronization (~/.tqsl)
macOS runs App Store and hardened-runtime software inside isolated **App Sandboxes**. The standalone TQSL desktop application stores its databases and certificates in the user's home directory:
```text
~/.tqsl/station_data
~/.tqsl/config.xml
```
Sandboxed applications cannot freely read this path and are restricted to their container:
```text
~/Library/Containers/ASIS.YAAM/Data/.tqsl/
```
**YAAM's Automated Storage Bridge:**  
YAAM contains a dedicated sync engine (`TQSLService.synchronizeTQSLStorage`). On application launch and prior to any signing execution, modification timestamps between `~/.tqsl` and the container directory are reconciled, copying updated station records and certificates transparently.  
In addition, `Settings > LoTW` features a manual sync button:
```text
[ Sync TQSL Data (~/.tqsl) ]
```
Whenever you add a new location or renew a certificate inside the official TQSL GUI, click this button to mirror the changes instantly into YAAM.

### 2.5 Importing .p12 Container Certificates & Keychain Security
* In `Settings > LoTW`, click **Choose .p12...** to select your exported TQSL certificate file. YAAM establishes a persistent **Security-Scoped Bookmark** to maintain safe filesystem access across macOS reboots.
* Passwords for your certificates and LoTW web accounts are protected in a **Hardware-Bound Keychain Vault**, encrypted with AES-256-GCM using hardware keys derived from your Mac’s unique serial number (`IOPlatformUUID`).

### 2.6 Zero-Click Cloud Upload Background Daemon
Enable **Zero-Click LoTW Upload** in settings. Whenever a QSO is finalized in Quick Log or via FT8, the background daemon bundles the contact, cryptographically signs it with TQSL, and uploads it to ARRL servers without requiring manual button clicks. Successfully uploaded QSOs are marked with `LOTW_QSL_SENT = Y`.
* **Outbox:** New QSOs are sent or queued only for enabled services with usable settings. Pending uploads wait while the Touch ID credential vault is locked; YAAM checks their service settings after unlock. Network failures retry automatically for up to seven days; older items remain in the outbox for a manual **Upload Outbox Now** attempt. Rejected requests retain their QSO for manual retry after settings are corrected. Existing paused entries from earlier versions remain in the outbox. The outbox holds at most 500 upload requests and warns when an older request is displaced.

### 2.7 Bi-Directional Reconciliation in QSL Hub
In the **QSL Hub** workspace, click **Fetch LoTW Confirmations** to download matched confirmations. The reconciliation engine uses a 30-minute matching window for time drift tolerance. Verified contacts turn bright green in your log table with `LOTW_QSL_RCVD = Y`.

---

## 3. CW Academy & Goertzel Audio Decoder

A comprehensive environment for learning, practicing, and decoding International Morse Code.

### 3.1 40-Lesson Koch Method Training
The Koch method builds auditory reflex recognition of complete character rhythms rather than counting dots and dashes. Training begins in Lesson 1 with 2 characters (`K` and `M`) and progresses across 40 lessons to encompass the full alphabet, numbers, punctuation, and procedural prosigns (`<AR>`, `<SK>`, `<BT>`). Advancement to the next lesson requires maintaining >= 90% accuracy.

### 3.2 Farnsworth Timing Mechanics
Listening to slow CW (e.g. 5 WPM) encourages mental dot/dash counting, creating a plateau at 10 WPM. YAAM implements true Farnsworth timing:
* **Character Speed (WPM):** Fixed at 20 WPM to instill proper rhythmic muscle memory.
* **Effective Speed (WPM):** Extends inter-character and inter-word pauses (e.g. 12 WPM) to provide the brain ample processing time.

### 3.3 Morse Echo Trainer
The system sends a random character or callsign; the operator immediately reproduces it using paddles, a serial port key, or the keyboard. YAAM measures reaction latency and accuracy percentage, recycling missed characters into subsequent trials.

### 3.4 Real-Time Wideband Quadrature DSP Audio & File Decoder
Connect your transceiver’s headphone/line-out audio to your Mac or import recorded audio files directly:
* **Wideband Analytic Demodulator (300 Hz – 1800 Hz):** Replaced legacy narrow Goertzel filters with a dual-channel Quadrature I/Q Analytic Demodulator (\(I[n] = x[n] \cos(\omega n)\), \(Q[n] = -x[n] \sin(\omega n)\)) and 65 Hz Butterworth lowpass filter. Completely eliminates high-frequency tone suppression and spectral leakage.
* **⚡ AUTO-TUNE Pitch Hunting:** Instantly scans the 300–1800 Hz audio spectrum using a Hann-windowed filter bank to lock onto the strongest CW carrier with zero operator calibration.
* **Continuous Auto-Tracking & AFC:** Dynamically tracks receiver pitch drifting and transmitter offset within \(\pm 60\) Hz.
* **Adaptive Schmitt Trigger & Leaky Envelope Followers:** Tracks signal peak and noise floor baselines with asymmetric attack/decay, yielding flawless decoding in high-noise environments down to +6 dB SNR.
* **Audio File Import & Decoding:** Decode pre-recorded Morse transmissions directly from `.m4a`, `.wav`, `.mp3`, or `.aiff` files via the **Decode File...** button.
* **Real-time Adaptive WPM & Paris Timing:** Accurately adapts between 5 and 50 WPM with real-time Dit/Dah ratio and SNR telemetry.

### 3.5 K1EL WinKeyer Hardware Drivers & Serial Keying
* Native USB serial communication with **K1EL WinKeyer** chipsets (WK2, WK3). Microsecond-precision hardware keying eliminates USB jitter.
* Full support for Iambic A, Iambic B, Ultimatic, and Bug modes.
* Direct DTR/RTS serial line keying support.
* **Your own callsign is required to transmit.** CW (keyer, Auto-CQ, contest Enter key and function keys, decoder reply), RTTY/PSK, Hellschreiber, Olivia, JS8, the SSTV test card, FT8/FT4 and the hardware test texts send nothing until the active station profile in `Settings > Stations` has your callsign (FT8/FT4 also need your locator). The reason is shown on the screen where you pressed the key: "Set your callsign in Settings > Stations before transmitting." when none is entered, or a message that the callsign is not accepted when it is entered but does not look like a callsign. The `Audio Sidetone Only` mode keys no radio and does not need one.

### 3.6 Comprehensive Q-Code and Contest Abbreviation Lexicon
Built-in reference library for instant lookup of standard Q-codes (QTH, QSL, QSY, QRM, QRN) and contest abbreviations (5NN, TU, BK).

---

## 4. Shack HamClock & Remote Web Server

### 4.1 Multi-Pane Station Dashboard & Universal Coordinated Time (UTC)
Modern dual-clock presentation featuring concurrent analog and digital displays for UTC and Station Local Time, continuously synchronized with Apple Network Time.

### 4.2 Live Solar & Geomagnetic Space Weather Indices
Direct telemetry from NOAA/SWPC space weather prediction centers:
* **SFI (Solar Flux Index):** 10.7 cm solar radio flux.
* **SSN (Sunspot Number):** Active sunspot region count.
* **A-Index & Kp-Index:** Planetary geomagnetic storm severity indicators (Green: Quiet, Yellow: Unsettled, Red: Storm).

### 4.3 Real-Time NASA SDO Imagery & DRAP D-Region Absorption
* Live extreme ultraviolet AIA 304Å feeds from NASA’s Solar Dynamics Observatory to spot coronal mass ejections (CMEs) and solar flares.
* Global DRAP (D-Region Absorption Predictions) map to assess High Frequency signal blackouts.

### 4.4 Local Network Web Server for iPad, Tablets & Second Monitors
Activate the Remote Shack Server on port 8080. YAAM starts a lightweight Server-Sent Events (SSE) web server. Open `http://<your-mac-ip>:8080` on an iPad or auxiliary display to view a synchronized, hands-free shack clock with grayline terminator projection.

---

## 5. Tactical Pilot HUD & HF Propagation Engine

### 5.1 VOACAP Point-to-Point Raytracing Engine
Input any callsign or DXCC entity. YAAM plots Great Circle Short Path and Long Path headings, total distance in kilometers/miles, and ionospheric bounce midpoints across flat and 3D globe projections.

### 5.2 Maximum Usable Frequency (MUF) & Signal-to-Noise (SNR) Metrics
Theoretical modeling of ionospheric E, F1, and F2 layers along the circuit:
* **MUF (Maximum Usable Frequency):** The highest frequency refracted between terminals. Frequencies operating between 85% and 90% of MUF yield the lowest attenuation.
* **SNR Estimation:** Modeled receiver signal-to-noise ratio in decibels based on transmitter power and antenna gains.

### 5.3 Tactical Band Advisor
Evaluates all 11 amateur HF/VHF bands (160m through 6m), categorizing each into **OPTIMAL**, **OPEN**, **MARGINAL**, or **CLOSED** states with predicted opening windows.

---

## 6. Station Weather Radar & Lightning Safety Protocols

Tall antenna towers and rotators are prime targets for lightning strikes and wind damage.

### 6.1 NEXRAD Doppler Precipitation Radar
Overlay live high-resolution Doppler precipitation radar reflecting storms over your station's Maidenhead grid locator.

### 6.2 Real-Time Cloud-to-Ground Lightning Discharge Tracking
Monitors cloud-to-ground electrostatic discharges within a 100-kilometer radius, calculating distance and bearing to the nearest active strike.

### 6.3 Mast, Rotator & Equipment Safety Distance Rings
* **Green Zone (> 30 km):** Normal operation; antennas and linear amplifiers safe to operate.
* **Amber Warning (15 to 30 km):** Storm system approaching; prepare to stow rotators to prevailing wind direction and power down high-voltage amplifiers.
* **Red Hazard (< 15 km):** **Immediate Equipment Disconnect Alert!** Unplug coaxial feedlines, ground antenna switches, and disconnect station power to protect sensitive receiver front-ends from induced voltage spikes.

---

## 7. Satellite Pass Tracking & High-Altitude APRS Balloons

### 7.1 Low-Earth Orbit Pass Predictions (AO-91, ISS, SO-50)
Automated ingestion of Two-Line Element (TLE) orbital sets from Celestrak and AMSAT for active amateur satellites and the International Space Station. Calculates Acquisition of Signal (AOS), Loss of Signal (LOS), pass duration, and Maximum Elevation.

### 7.2 Real-Time VHF/UHF Doppler Shift Correction
Computes instantaneous relative velocity and frequency shift, presenting adjusted TX and RX frequencies to maintain clear audio during low-Earth orbit passes.

### 7.3 APRS High-Altitude Balloon Telemetry Tracking
Decodes and plots real-time telemetry from stratospheric APRS research balloons, displaying altitude, ascent/descent rate, barometric pressure, and ground track.

---

## 8. Digital Contest Suite (FT8/FT4) & Master.scp Database

### 8.1 Official CQ WW Digi & ARRL Digi Workflows
Specialized contest logging engine supporting official scoring rules for CQ World Wide Digi DX and ARRL Digi Contests, computing points based on Maidenhead grid distances and DXCC entities.

### 8.2 Bi-Directional UDP Stream with WSJT-X & JTDX
Seamless integration over UDP: clicking any decoded station inside YAAM issues an immediate Reply command (Packet Type 4) or Halt TX command (Packet Type 7) to WSJT-X without window switching.

### 8.3 Multiplier Matrix & Rate/Hour Speedometer
A dynamic matrix displays worked vs. needed Maidenhead field multipliers (e.g. JO, JN, LL) and DXCC entities. A live speedometer calculates your rolling 60-minute contact rate (Rate/Hr).

### 8.4 Pre-Submission Validation & Cabrillo 3.0 Generation
Runs syntax and scoring checks before generating the final Cabrillo 3.0 `.log` file, ensuring error-free robot acceptance.
From 50 MHz upward, the Cabrillo frequency field uses a band designator such as `50`, `144`, or `1.2G`; lower frequencies use kHz.

### 8.5 Interactive Super Check Partial (SCP) & Contest Intelligence HUD
As you type callsigns into QuickLog, the CW Keyer, or the CW Pileup Simulator (after 2 or more characters), YAAM queries the bundled `Master.scp` database in real time with sub-millisecond latency.
* **Smart Ranking & Matching:** Exact matches appear first, followed by high-relevance prefix and substring matches.
* **Country Flag & DXCC Identification:** Automatically displays entity emoji flags and names.
* **Live Contest Status Badges:**
  - 🟠 **`MULT`:** Unworked DXCC entity (new multiplier).
  - 🟢 **`NEW`:** Valid callsign unworked on current band/mode.
  - ⚪️ **`DUPE`:** Callsign already logged on the current operational band and mode.
* **1-Click Autocomplete:** Click any callsign pill in the HUD to immediately fill the callsign field.

---

## 9. Operator Desk & Direct Icom MK2 LAN Architecture

Operator Desk is organized into six workspaces: **Operating**, **DX Activity**, **Radio & Digital**, **CW Workstation**, **Contest & Awards**, and **QSL & Data**. Choose a workspace in the upper row, then a tool in the lower row. When the tool strip cannot fit, its menu lists every tool in that workspace. **All tools** searches the entire desk, including familiar older names.

- Radio Bridge, FLRig, TCI SDR, Rotator, FT8 Station, Multi-Rig FT8, Digital Suite, and Emulator each have one destination under **Radio & Digital**.
- WinKeyer diagnostics and the complete CW hardware setup are under **CW Workstation → WinKeyer & Hardware**.
- DXpedition schedules and bulletins live in **DX Activity → DX News**. **Contest & Awards → Contest Calendar** links to them and focuses on contest planning.
- **QSL & Data → QSL Hub → Sync Confirmations** downloads online confirmations. Its ellipsis menu includes LoTW-only and QRZ-only sync.
- **QSL & Data → Log Sources & Automation → Sync Local Logs** imports External ADIF and SDR-Control updates. Wavelog has its own sync button. The existing automatic schedule still covers local logs plus LoTW and QRZ; its saved settings are preserved.
- **Cloud & Companion** contains cloud folder packages, the mobile companion, and the local API. **Labels & Printing** contains the QSL label designer.

Each workspace remembers its last tool. Existing operating shortcuts remain; Log Sources & Automation is **Command-Option-Shift-S**, leaving **Command-Shift-S** for Save As. Separate windows are under **Tools → Open in Separate Window**.

For operators of the **IC-7300MK2**, **IC-7610**, and **IC-705**:
* Direct Ethernet and Wi-Fi LAN connection eliminating external USB cables and virtual COM port drivers.
* CI-V rig control packets on UDP port 50001; low-latency 48 kHz 16-bit uncompressed digital audio stream on UDP port 50002.
* Real-time meters for Forward RF Power, ALC levels, and SWR with configurable safety thresholds.
* Dynamic hardware watchdog that auto-releases PTT in the event of packet loss or network interruption.

---

## 10. Digital Call Roster with Speech Synthesis Alerts

The Digital Call Roster inspects every incoming FT8/FT4 decode against your logbook and prioritizes targets:
* ⭐️ **NEW DXCC (ATNO):** All-Time New One on any band (highest priority).
* 🎯 **NEW BAND:** Confirmed DXCC entity, but needed on this operational band.
* 💠 **NEW GRID:** Unworked 4-character Maidenhead grid for VUCC credit.
* 🔔 **CALLING ME:** An operator directing a transmission specifically to your callsign.
* **macOS Speech Synthesizer Alerts:** Hands-free voice announcements (e.g., *"New DXCC! Japan on 14 Megahertz"*).

---

## 11. Logbook Table Modernization & Confirmation Credit Intelligence

* **Centered Leaderboard Columns:** Centered formatting for `Band Rank`, `DXCC Rank`, and `QSO Rank`.
* **UTC Chronological Ordering:** Filtered views cleanly indexed from 1 (most recent QSO) descending.
* **Confirmation Credit Tracking:**
  * **BAND CREDIT:** Indicates `NEW` (opportunity for first confirmation on this band), `HAVE` (country previously confirmed on this band), or `DONE` (this contact is confirmed).
  * **GRID CREDIT:** Highlights unconfirmed Maidenhead grids.
* **DXCC Entity Normalization:** Robust entity parsing resolving ambiguous prefixes and correctly differentiating European and Asiatic Russia.

---

## 12. Today's QSL Card Image Batch Dispatcher

For contacts confirmed today:
* Automatically generates two-page, high-resolution vector PDF QSL cards (Page 1: station artwork; Page 2: cryptographic QSO confirmation endorsement).
* Direct email dispatch via your personal SMTP credentials.
* **Anti-Duplication Guard:** QSOs previously mailed are flagged `Already Sent` to prevent duplicate emails.
* Embeds official national emoji flags corresponding to recipient DXCC entities.

---

## 13. Tactical Rover Mode & Grid Scout

**Tactical Rover Mode** enables operators to temporarily relocate their station to alternate Maidenhead grids (e.g. SOTA summits, POTA parks, VHF/UHF rover grids) **without altering or corrupting the permanent station profile in the SQLite database**.

### Key Architectural Capabilities:
1. **In-Memory Station Projection:**  
   The `RoverModeEngine` overlays the rover grid and coordinates in volatile memory. All system modules—**3D Globe**, **Tactical Pilot**, **Bandmap**, **Weather Radar**, and **DX Cluster**—immediately adjust antenna azimuths, path calculations, and propagation curves.
2. **4-Way Compass Stepper:**  
   When traveling in a vehicle, tapping **North**, **South**, **East**, or **West** steps the Maidenhead locator to adjacent squares. The engine handles 360-degree longitude wrap-around and polar latitude clamping while preserving precision 6-character subsquares (e.g. `LL46ab` -> `LL47ab`).
3. **Outbound QSO Stamping:**  
   Enabling *Stamp MY_GRIDSQUARE in outgoing QSOs* records the rover grid in all contacts logged via Quick Log or FT8, ensuring compliant logs for POTA activators and contest rovers.
4. **Live Geodesic Telemetry & Astronomical Solar Clock:**  
   Continuously displays great-circle distance, forward bearing to home QTH, 16-point compass heading, and local solar sunrise/sunset times.
5. **Auto-Expiration Safeguard:**  
   Configure sessions for 1 Hour (Quick Scout), 4 Hours, 8 Hours, End of UTC Day, or Manual Indefinite. When time expires, YAAM reverts smoothly to your home QTH with voice confirmation.
6. **Top Navigation Status Pill:**  
   An amber glowing pill in the window title bar displays your active grid and remaining session time, offering 1-click access to rover controls.

---

## 14. Spectrum Bandmap & Waterfall Studio

A unified 3-pane panadapter environment:
1. **Vertical Frequency Ruler (Left Pane):**  
   Precision frequency scale with color-coded band segments for CW, Digital/Data, and Phone (SSB) adhering to IARU Regions 1, 2, and 3. DX cluster spots are mapped directly onto the ruler with freshness decay indicators.
2. **Live SDR Spectrum & Waterfall (Center Pane):**  
   Real-time FFT spectrum analyzer with variable zoom (0.5x to 4x), peak hold detection, and continuous waterfall history.
3. **DX Spot Hunter Table (Right Pane):**  
   Curated spot list with 1-click filtering for All-Time New Ones (ATNO), needed bands, and SNR thresholds, paired with a **Tune Rig** CAT button.
4. **Dual VFO Tracking & Split Operations:**  
   Concurrent visual markers for VFO A (green, transmit/receive) and VFO B (orange, split pile-up listening).
5. **Thermal Heatmap Ribbon:**  
   Aggregates 15-minute QSO density to reveal intense pile-up activity before signals are heard on the air.
6. **Multi-Band Panorama:**  
   Monitor the top 4 contest bands (40m, 20m, 15m, 10m) simultaneously in a 2x2 grid.

---

## 15. QSL Card Label Studio

Print physical QSL labels for QSL Bureau or direct postal mail with precision layout controls:
1. **Worldwide Format Support:**  
   Preconfigured for **Avery** standards (Avery 5160 30-up, 5162 14-up, 5163 10-up) and European **A4** sheets (L7160 21-up, L7162 16-up).
2. **Interactive Peel-Off Skip Matrix:**  
   Label sheets are costly. If you have a partially used sheet, click the used slots in the preview matrix; YAAM marks them `SKIPPED` and begins printing on the first virgin label.
3. **Sub-Millimeter Printer Calibration:**  
   Fine-tune horizontal (X) and vertical (Y) print offsets in 0.1 mm increments to eliminate tray alignment drift on any macOS printer.
4. **Intelligent Source Filtering:**  
   Print labels for recent contacts, unconfirmed QSOs awaiting cards, or dedicated contest logs.
5. **Direct Printing & Vector PDF:**  
   Send jobs directly to macOS print queues or export crisp, vector-rendered multi-page PDF files.

---

## 16. International Club Memberships

Instantly detect and recognize members of specialized international amateur radio societies:
1. **Supported Organizations:**  
   * **SKCC (Straight Key Century Club):** Mechanical key membership numbers and Centurion/Tribune/Senator ranks.
   * **CWops:** High-speed CW operators club for weekly CWT contests.
   * **FISTS:** International Morse preservation society.
   * **LICW (Long Island CW Club):** CW training community.
   * **30MDG & EPC:** 30-meter and digital mode specialty groups.
   * **A1 Club:** Premier Japanese CW club.
2. **Instant Recognition & 1-Click Exchange Insertion:**  
   Typing a callsign in Quick Log or Contest Mode instantly queries the local database and displays club badges. Press `Cmd + E` to insert member numbers directly into exchange fields.
3. **Offline SQLite Engine:**  
   Over 38,000 active member records stored locally for instantaneous (<2 ms) lookup without an internet connection.

---

## 17. Club Log Live Spots & Band Intelligence Engine

Real-time spot intelligence powered by Club Log feeds:
1. **Band Opportunity Engine:**  
   Scores band activity relative to your verified logbook:
   Score = Total Spots + (Needed DXCC * 3.5)
   This highlights bands with the highest potential for new DXCC credits rather than simply the most crowded bands.
2. **Station Identity Status Badges:**  
   * **ATNO (All-Time New One):** Country never before worked on any band (prominent purple).
   * **NEEDED BAND:** Confirmed on other bands, but unconfirmed here (prominent green).
   * **CONFIRMED:** Country credit already secured for this band.
3. **Dominant Mode Detection:**  
   Reveals whether opening activity is centered on FT8, CW, or Phone.
4. **1-Click QSY:**  
   Click **Tune Rig** to issue CAT commands to your transceiver and populate Quick Log fields instantaneously.

---

## 18. Network-Attached Transceiver Emulator (NTE)

The Network-Attached Transceiver Emulator provides complete hardware-level emulation of modern Ethernet/WLAN transceivers (specifically Icom IC-705, IC-7300/MK2, IC-7610, and IC-9700), along with a built-in Hamlib `rigctld` server.

### Key Capabilities:
1. **Full Protocol Emulation (CI-V over IP & Hamlib)**:
   * **Icom LAN UDP Channels:** Control channel (`50001`), CI-V register channel (`50002`), and 48 kHz LPCM16 audio streaming channel (`50003`).
   * **Hamlib rigctld Server:** Multi-client TCP server on port `4532` allowing immediate connection by WSJT-X, JTDX, N1MM, and other software without external bridging daemons.
   * **Local LAN Auto-Discovery:** Broadcasts and responds to UDP discovery probes so third-party applications (wfview, SDR-Control) find the emulator just like a physical radio.
2. **Synthetic RF & Channel Physics Engine**:
   * **Calibrated AWGN:** Adjust Signal-to-Noise Ratio (SNR) continuously from `-30 dB` to `+30 dB`.
   * **Ionospheric Multipath Fading:** Simulates Clean direct path, Mild QSB (0.2 Hz), Deep Rayleigh flutter (1.5 Hz), and high-Doppler Auroral flutter (4.0 Hz).
   * **Doppler Shift & Drift:** Carrier frequency shift up to `±500 Hz` with linear drift up to `±100 Hz/min` (simulating satellite passes and ionospheric motion).
   * **Atmospheric Static (QRN):** Injects impulsive static bursts.
   * **Network Stress Injection:** Configurable simulated packet loss (0% to 25%) and latency jitter (0 to 100 ms).
3. **Synthetic Signal Studio**:
   * **FT8/FT4 Generator:** Real-time continuous-phase FSK synthesis with UTC 15-second / 7.5-second slot alignment.
   * **5-Station Pileup Simulator:** Generates simultaneous calling stations on distinct audio offsets with varying SNR levels.
   * **CW Morse Beacon:** 20 WPM beacon with smooth raised-cosine envelopes to prevent spectral key clicks.
4. **Automated DSP Benchmarking**:
   * One-click **SNR Sensitivity Sweep** from `+6 dB` down to `-24 dB` in 3 dB increments to measure receiver decoding thresholds and output markdown reports.
5. **Interactive Front Panel UI**:
   * High-contrast OLED display with digital VFO, active band pill, S-meter / RF Power / SWR meter, tuning buttons, and latching PTT.
   * Quick **Connect YAAM LAN** button links YAAM's own client directly to the emulator for immediate loopback evaluation.
   * Access via Operator Desk (Section 24), Tools menu (`Cmd + Option + E`), or as a standalone detached window.

---

## 19. Super Check Partial (SCP) & Call History Predictive Exchange Engine

YAAM features high-speed predictive callsign verification and contest exchange pre-fill:
1. **Super Check Partial (SCP) HUD:**
   * Instant search across thousands of active contest callsigns as you type (minimum 2 characters).
   * Visual badge indicators: **NEW MULT** (orange with star), **NEW CALL** (green), and **DUPE** (dimmed grey) based on your real-time logbook.
   * DXCC flag icons and country names for immediate geographical orientation.
2. **Call History Lookup & Exchange Pre-fill:**
   * Ships with an internal seed database of top worldwide contesters and self-learns from every QSO logged in YAAM.
   * Full support for importing standard N1MM / Win-Test `CallHistory.txt` files (`importCallHistory`).
   * When a callsign is recognized, an interactive pre-fill banner appears under the callsign field.
   * Press **Spacebar** or click **Pre-Fill (␣)** to automatically populate Operator Name, US State, CQ Zone, ARRL Section, Grid Square, and Contest Exchange without touching the keyboard.
3. **Macro Token Expansion:**
   * CW Keyer and ESM macros now expand `{HISNAME}`, `{HISSTATE}`, `{HISZONE}`, `{HISSECT}`, `{HISGRID}`, and `{HISEXCH}` dynamically during transmission.

---

## 20. Interactive Visual Contest Bandmap HUD

Designed for rapid Search & Pounce (S&P) operation without opening separate windows:
1. **Vertical Frequency Ruler:**
   * Embedded directly in the Quick Log / ESM contest toolbar via the **[Bandmap]** button.
   * Displays incoming cluster spots and CW Skimmer decodes along a high-contrast vertical frequency axis for the active band.
2. **Visual Status Badges & Age Decay:**
   * Spots are color-coded by contest multiplier value: Orange (`MULT`), Green (`NEW`), and Grey (`DUPE`).
   * Temporal opacity decay ensures visual clarity: fresh spots appear at 100% brightness, decaying gradually to 75% at 10 minutes, 45% at 20 minutes, and 25% past expiration.
3. **1-Click CAT QSY:**
   * Clicking any spot on the Bandmap instantly tunes your physical transceiver (via CI-V / Hamlib / FLRig) and pre-fills the callsign and predicted exchange into Quick Log.

---

## 21. Contest Rate Speedometer & Multiplier 2D Matrix Dashboard

Monitor your operating momentum and maximize contest score in real time:
1. **Circular Rate Speedometer:**
   * Displays your rolling 10-minute rate (`QSO/h`) with a dynamic gradient sweep from cool blue (cruising) to blazing orange/amber (high run rate).
   * Secondary indicators track rolling 60-minute rate, session peak hourly rate, active consecutive QSO streaks, and total on-air operating time.
2. **2D Band x Multiplier Matrix Heatmap:**
   * Comprehensive matrix spanning all HF contest bands (160m, 80m, 40m, 20m, 15m, 10m, and 6m).
   * Breaks down QSOs, unique DXCC entities worked, and CQ Zones worked per band.
   * Total summary row highlights overall multiplier accumulation for instant Cabrillo score projection.
   * Toggle view on/off anytime with the **[Rate Matrix]** button in the contest header.

---

## 22. Hardware Paddle Break-In & Instant Macro Interrupt Handler

Full hardware-level safety and interrupt handling for CW contesters:
1. **Instant Paddle Break-In:**
   * WinKeyer hardware status bytes (`0xC0...0xCF`) are continuously scanned in real time.
   * Touching either paddle paddle (Dit or Dah) during automated macro sending or Auto-CQ instantly aborts transmission and cuts off the audio sidetone within milliseconds.
2. **Visual Warning Badge:**
   * A vibrant red `[⚡ PADDLE BREAK-IN]` warning badge displays on the contest toolbar when manual paddle override occurs, decaying gracefully after 1.5 seconds.

---

## 23. Lab599 Discovery TX-500: USB-C Integration (Digital & Morse Modes)

YAAM features native, driver-level integration for the ultra-compact **Lab599 Discovery TX-500** HF/6m QRP transceiver over macOS USB-C ports.

### 23.1 Dual-Channel USB-C Cable Topology
The TX-500 requires two separate hardware channels connected to your Mac:
* **Channel 1 — Serial CAT Control (GX12 4-Pin):**
  Connect the transceiver's `CAT` connector via the Lab599 **AD-514** (or **AD-502**) cable. The integrated FTDI FT232R USB-to-UART bridge mounts on macOS as `/dev/cu.usbserial-*`.
* **Channel 2 — Analog Baseband Audio (GX12 7-Pin):**
  Connect the transceiver's `REM/DATA` port via the Lab599 **AD-508** (or **AD-509**) USB-C audio codec. macOS CoreAudio recognizes this device as `USB Audio Device` operating at 48.0 kHz 16-bit PCM.

### 23.2 Transceiver Menu Configuration (Pre-Flight Checklist)
Ensure your TX-500 has the following settings configured in its hardware menu:
1. **`Menu 34 (CAT MODEL): TS2000`** — Sets Kenwood TS-2000 emulation mode.
2. **`Menu 35 (CAT SPEED): 9600`** — Sets communication baud rate to 9600 bps (8 data bits, no parity, 2 stop bits — **8N2**).
3. **`Menu 09 (CAT PTT-TO): 30`** — Sets hardware PTT safety timeout to 30 seconds.
4. **Operating Mode:** Select **`DIG`** directly on the radio front panel.

### 23.3 Firmware Bug #1 Mitigation: `preserveDIGMode`
> [!IMPORTANT]
> In TX-500 firmware (v1.30.00), transmitting while sending standard CAT mode change commands (`MD`) forces the transceiver from `DIG` mode into voice `USB` mode. In voice `USB`, the REM/DATA baseband input is electronically muted, causing the radio to key up with **0 Watts RF output**.
>
> YAAM includes an automatic safety lock: **Preserve DIG Mode** (`preserveDIGMode: true`). When operating in FT8, FT4, RTTY, or PSK31, YAAM deliberately omits CAT mode override commands upon transmission, guaranteeing the transceiver remains locked in hardware `DIG` mode with full RF power delivery.

### 23.4 Digital Modes Operation (FT8, FT4, RTTY, PSK31)
1. In the **FT8 / FT4 Station View** or **Digital Modem**, set the audio/radio path to **Lab599 TX-500**.
2. Select your `/dev/cu.usbserial-*` port and the `USB Audio Device` input/output.
3. Click **Connect**; the connection pill turns green and live frequency and S-meter telemetry synchronize.
4. Transmit sequences automatically assert CAT PTT (`TX;` / `RX;`) protected by a strict 14.0-second safety watchdog.

### 23.5 Morse / CW Keying & Audio Decoding
1. In the **CW Keyer** or **CW Academy**, set transmission mode to **`Lab599 TX-500 (USB-C CAT & Pin)`**.
2. **CAT Buffer Keying:** Characters typed into Quick-Transmit or contest macros are buffered into 24-character bursts via Kenwood `KY <text>;` commands with speed set via `KS<wpm>;`.
3. **Hardware Pin Keying:** Optional DTR/RTS line keying directly pulses the serial port's hardware pins.
4. **Audio Decoding:** Received CW baseband audio from the AD-508 adapter feeds the real-time Goertzel DSP decoder (`CWAudioDecoderEngine`) with auto-tracking tone filters.

### 23.6 Diagnostics Workbench
Access the dedicated diagnostics workbench via **Preferences -> Lab599 TX-500** or the Rig Control toolbar card:
* **Interactive PTT Test:** 1-second pulse test to verify relay engagement without full RF burst.
* **CW Test Burst:** Sends a brief test string (`TEST DE` followed by the callsign saved in `Settings > Stations`) to verify CAT buffer timing. Without a saved callsign it sends nothing and shows "Set your callsign in Settings > Stations before transmitting."
* **Live S-Meter & Power Bar:** Displays real-time signal strength (`SM0;`, the radio's 0 to 30 count shown as S0 to S9+60 dB) and transmitter status (`IF;` / `PC;`).

---

## 24. Xiegu X6100: USB-C Integration (Digital & Morse Modes)

YAAM features native, driver-level integration for the **Xiegu X6100** SDR QRP HF/50MHz transceiver over a single macOS USB-C cable without requiring third-party middleware (such as Hamlib or FLRig).

### 24.1 Hardware Architecture: Single-Cable USB-C `DEV` Port vs `HOST` Port
> [!IMPORTANT]
> The Xiegu X6100 possesses two USB-C ports on its left panel: **`DEV`** and **`HOST`**.
> * **Always connect your Mac to the `DEV` (Device) port.**
> * The `HOST` port is reserved exclusively for peripheral devices (mouse, keyboard, external USB storage) and will not enumerate on macOS as a serial CAT or audio device.

A single standard USB-C cable connected to the `DEV` port provides two concurrent hardware channels:
1. **Serial CAT Communications (Dual-UART):**
   * The X6100 internal USB controller enumerates two serial ports on macOS (typically `/dev/cu.usbserial-xxx` or `/dev/cu.usbmodem*` or `wchusbserial`).
   * **Port B (the higher index):** Dedicated to CI-V CAT rig control and CW keying.
   * YAAM's intelligent port scanner automatically discovers and selects Port B.
2. **Integrated Bidirectional USB Audio CODEC:**
   * CoreAudio enumerates the internal sound card as **`USB Audio CODEC`** or **`X6100 Audio`**.
   * YAAM streams 48.0 kHz 16-bit PCM baseband audio with zero analog loss, hum, or cable clutter.

### 24.2 Icom IC-705 CI-V Emulation Protocol & Serial UART Settings
The Xiegu X6100 internal baseband Linux OS natively emulates the **Icom CI-V** communication protocol (matching the IC-705 subset).
* **Default CI-V Address:** `0xA4` (matching Icom IC-705).
* **Controller Address:** `0xE0` (standard master controller).
* **Default Baud Rate:** `19200` bps, 8 Data Bits, No Parity, 1 Stop Bit (**8N1**). Rates up to `115200` bps are supported.
* **CI-V Transceive:** When enabled, tuning the VFO knob on the radio instantly reflects on the YAAM spectrum and dial indicators in real time.

### 24.3 Integrated USB Audio CODEC Configuration in macOS CoreAudio
1. In YAAM **FT8 Station View** or **Settings -> Xiegu X6100**, the audio input and output devices are detected automatically.
2. Audio streaming runs at 48.0 kHz with hardware sample rate conversion if needed.
3. Ensure the microphone permission is granted in macOS `System Settings -> Privacy & Security -> Microphone`.

### 24.4 Digital Modes Operation (FT8, FT4, RTTY, PSK31), Auto USB-D & PTT Watchdog
1. **Radio Path Selection:** Set the radio path in FT8 Station View or Digital Modem to **`Xiegu X6100 (USB-C)`**.
2. **Automatic USB-D Switching:** When selecting any FT8 or digital band, YAAM automatically sends CI-V mode commands (`06 01 01` & `1A 06 01 01`) to engage **USB-D** (digital data mode) and adjust IF filter bandwidth.
3. **Fail-Safe PTT Watchdog:**
   * Digital transmission commands issue CI-V PTT ON (`1C 00 01`).
   * An autonomous hardware watchdog timer enforces a maximum 16.0-second transmission window. If transmission stalls or connection drops, PTT OFF (`1C 00 00`) is asserted automatically to protect the final RF amplifier stage.
4. **QRP Power Setting:** Transmit power can be adjusted between 1W and 10W (external 13.8V supply) or 1W and 5W (internal battery) via standard CI-V commands (`14 0A`).

### 24.5 Morse Code (CW) Keying via CI-V Command 17 Buffer & Hardware DTR/RTS Pin Keying
YAAM offers two distinct Morse code transmission modes for the X6100:
1. **CI-V Command 17 Text Buffer Keying (Recommended):**
   * Pre-formatted ASCII text from the CW Keyer or contest macros is transmitted directly to the X6100 internal keyer buffer via CI-V frame: `FE FE A4 E0 17 <ASCII> FD`.
   * The radio's internal firmware generates perfectly shaped dits and dahs with zero macOS timing jitter.
   * **WPM Speed Sync:** Speed changes in YAAM automatically synchronize the radio keyer speed via CI-V command `14 0C <speed>`.
   * **Instant Abort:** Pressing `Escape` or clicking `Stop` instantly sends the CI-V break sequence `17 FF` to silence the transmitter.
2. **Hardware Serial Pin Keying (DTR / RTS):**
   * For direct paddle emulation or external software keying, YAAM can toggle the physical DTR or RTS lines of the USB-C serial port.
3. **Goertzel DSP Audio Decoding:**
   * Received CW audio from the USB Audio CODEC is routed to YAAM's Goertzel tone tracking decoder for live text transcription.

### 24.6 Diagnostics Workbench, S-Meter, SWR & ALC Real-Time Telemetry
Open **Settings -> Xiegu X6100** or the **Rig Control Toolbar** card to access the diagnostics workbench:
* **Interactive 1-Second PTT Pulse:** Confirms relay engagement without broadcasting sustained RF carrier.
* **CW Burst Test:** Sends a test burst (`TEST DE` followed by the callsign saved in `Settings > Stations`) to verify CI-V command 17 buffer operation. Without a saved callsign it sends nothing and shows "Set your callsign in Settings > Stations before transmitting."
* **Live Telemetry Bars:**
  * **S-Meter:** Real-time signal strength from `S0` to `S9+60dB` via command `15 02`.
  * **SWR Meter:** Reflected power monitoring via command `15 12`.
  * **ALC Indicator:** Real-time modulation headroom via command `15 13`.

---

## 25. Multi-Rig FT8 Cluster: Multi-Transceiver Operation (SO2R / SO3R)

The **Multi-Rig FT8 Cluster** is an advanced operational mode in YAAM designed for serious DXers and contest stations who want to operate **up to 4 independent transceivers simultaneously** across different amateur bands.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        YAAM Multi-Rig FT8 Cluster Console (SO3R)                       │
├────────────────────────────────────────┬───────────────────────────────────────────────┤
│ Slot 1: Icom LAN (IC-7610 / IC-705)    │ 20m (14.074 MHz) · Waterfall 1 · Audio Ch 1   │
│ Slot 2: Lab599 Discovery TX-500 (USB)  │ 40m (7.074 MHz)  · Waterfall 2 · Audio Ch 2   │
│ Slot 3: Transceiver Emulator / rigctld │ 10m (28.074 MHz) · Waterfall 3 · Audio Ch 3   │
├────────────────────────────────────────┴───────────────────────────────────────────────┤
│  Cross-Rig Hardware Interlock  ·  Cross-Band Opportunity Radar  ·  Unified SQLite Log  │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### 25.1 Architecture & Concept of Multi-Rig Operation
Managing multiple transceivers from a single computer is essential for:
* **SO2R (Single Operator 2 Radios):** Calling CQ or listening on one band while transmitting on another.
* **SO3R (Single Operator 3 Radios):** Tri-band coverage (e.g. 20m daytime DX, 40m night-time DX, and 10m sporadic-E monitoring).
* **Multi-Transceiver DX Hunting:** Spotting and working unworked DXCC countries or Maidenhead grids concurrently without manually band-switching.

### 25.2 Autonomous DSP Audio & CAT Pipeline Isolation
Each transceiver is hosted inside an autonomous `MultiRigSlot` container:
1. **Isolated DSP & Waterfall:** Each slot runs an independent `FT8EngineService` instance on dedicated Grand Central Dispatch queues with its own 3 kHz audio spectrogram waterfall.
2. **Audio Hardware Binding:** Each slot binds directly to a distinct CoreAudio device (e.g., `USB Audio CODEC`, network LPCM stream, or virtual cable). Transmit audio generated for Slot 1 will never leak into the input stream of Slot 2 or Slot 3.
3. **Driver Support:** Supports direct Icom LAN UDP (IC-705, IC-7300MK2, IC-7610, IC-9700), Lab599 TX-500 USB, Xiegu X6100 USB-C, Icom USB, Hamlib `rigctld`, and internal Network-Attached Transceiver Emulator.

### 25.3 Cross-Rig TX Interlock Coordinator
Keying multiple transmitters at once in a shared physical shack can cause severe receiver desensitization or damage to the sensitive receiver front-end. YAAM prevents this with its built-in hardware interlock coordinator:
* **Concurrent TX:** Allows all armed transceivers to transmit simultaneously (for stations with separate towers and high-grade bandpass filters).
* **Strict Lockout:** First-come, first-served mutual exclusion. Only one radio may assert PTT at any instant. Other radios wait until PTT is released.
* **Alternating Slots (SO2R Standard):** Synchronized to the UTC 15-second FT8 epoch:
  * Slot 1 transmits on even periods (`:00`, `:30`).
  * Slot 2 transmits on odd periods (`:15`, `:45`).
  * Slot 3 acts as a continuous receive monitor or standby runner.
* **Emergency Disarm (`Disarm All TX`):** Instantly cancels all transmissions and de-asserts PTT across all radios with one click.

### 25.4 Multi-Pane Console Layouts
Switch between 5 ergonomic layouts depending on your display setup:
1. **3-Column Parallel:** Side-by-side view with live waterfalls and decode logs for 3 transceivers.
2. **Hero + 2 Sub-Rigs:** High-resolution main band waterfall on top; two secondary bands side-by-side below.
3. **Dual Split:** 50/50 split for classic 2-radio SO2R operation.
4. **Quad Matrix:** 2x2 grid for up to 4 transceivers.
5. **Focused Single:** Full-screen focus on one slot with quick-switch tabs for the others.

### 25.5 Cross-Band DX Opportunity Radar
Located at the bottom of the console, the **Cross-Band DX Opportunity Radar** collates incoming CQ calls across all active slots:
* Analyzes calls in real time against your local SQLite logbook.
* Badges opportunities as **NEW DXCC**, **NEW BAND**, **NEW GRID**, or **CALLING ME**.
* **1-Click Answer:** Clicking `Answer on Rig X` tunes the audio offset, formats the response message, and queues transmission on that transceiver for the next time slot.

### 25.6 Unified Logbook Integration & Multi-Monitor Window (`Cmd + Option + 8`)
* **Unified SQLite Log:** All completed QSOs are saved to the central logbook with the originating radio stored in the ADIF `RADIO` field (e.g. `Rig 1 (20m FT8)`).
* **Instant Propagation of Worked Status:** A QSO logged on Slot 1 immediately updates the worked status on Slot 2 and Slot 3.
* **Dedicated Secondary Window Scene:**
  * Open via `Window -> Multi-Rig FT8 Cluster (SO3R)...` or shortcut `Cmd + Option + 8`.
  * Move the cluster window to a second monitor while keeping your primary display open for log analysis, maps, or awards tracking.

---

## 26. POTA & SOTA Field Operations Hub

Located under **Operator Desk → Operating → Portable** (or accessible by searching "POTA", "SOTA", or "Field Activation"), the **Field Operations Hub** provides a native macOS tactical companion for operators taking MacBook and QRP rigs (such as Lab599 Discovery TX-500, Elecraft KX2/KX3, FX-4CR, Xiegu X6100, and Icom IC-705) into the field.

### 26.1 Rapid Pileup Logger & HUD
* **Keyboard-First Ergonomics:** Full operation with keyboard only (`Space` for next field, `Enter` to log and auto-clear for next caller).
* **Outdoor Sunlight High-Contrast Mode:** Switchable high-visibility theme with large monospaced fonts and intense contrast designed for operation in glaring outdoor daylight.
* **10-QSO Milestone Dial:** Circular progress dial tracking contacts toward the official 10-QSO qualification threshold for POTA activations (or 4 QSOs for SOTA), complete with celebratory milestone banner and sound cues upon qualifying.
* **Real-Time CAT Sync:** Displays live transceiver VFO frequency, band, and mode from `RigControlEngine` and automatically stamps accurate RF telemetry into each QSO.

### 26.2 Live Spots & Park-to-Park (P2P) Radar
* **Direct API Feeds:** Ingests live spots from official POTA (`api.pota.app/spot/activator`) and SOTAwatch (`api2.sota.org.uk/api/spots`) with customizable auto-refresh.
* **Park-to-Park (P2P) Opportunities:** Automatically badges stations when you are in an active activation session, identifying mutual activation opportunities.
* **1-Click CAT QSY:** Instantly commands the connected transceiver (TX-500, IC-705, FX-4CR, Xiegu, FLRig, or Hamlib) to jump directly to any spotted station's exact frequency and mode.

### 26.3 Offline Park & Summit Directory with Native MapKit
* **Zero-Internet Dependency:** Bundles an offline curated database of international parks and summits with instant sub-millisecond search by reference, name, or country.
* **Proximity Calculation:** Automatically calculates distance in kilometers from your current station or Rover GPS coordinates.
* **MapKit Visual Explorer:** Interactive Apple Maps pins showing park boundaries and operator location with 1-click activation session launcher.

### 26.4 Official POTA & SOTA Log Export
* **Strict Filename Compliance:** Automatically formats export filenames adhering to official POTA rules: `[CALL]@[MY_POTA_REF]-[YYYYMMDD].adi`.
* **Mandatory ADIF Tags:** Automatically injects `MY_SIG=POTA`, `MY_SIG_INFO=[REF]`, `MY_POTA_REF=[REF]`, `POTA_REF=[CONTACTED_REF]`, `STATION_CALLSIGN`, and `OPERATOR`.
* **SOTA CSV v2 Support:** Generates valid SOTA Database CSV v2 records (`V2,MyCall,MySummit,DD/MM/YY,HHMM,Band,Mode,HisCall,HisSummit,Comment`) ready for upload to `sotadata.org.uk`.

---

## 27. Digital Callsign Monitor & Real-Time Activity Tracker (HamTracker)

Located under **Operator Desk → DX Activity → Digital Callsign Monitor** (or accessible via shortcut from Quick Log, Call Intelligence, or Competitor Watch), the **Digital Callsign Monitor (HamTracker)** is a workstation-grade tracking console based on the `ham_tracker.py` engine. It monitors real-time digital radio transmissions (FT8, FT4, JS8) and contact history for any amateur radio callsign worldwide.

### 27.1 Real-Time PSKReporter MQTT 3.1.1 Stream
* **Sub-Second Transmission Detection:** Directly connects to `mqtt.pskreporter.info:1883` over native Apple `Network.framework` TCP sockets, subscribing to `pskr/filter/v2/+/+/[CALLSIGN]/#`.
* **Zero Delay:** Catches new FT8/FT4 transmissions as soon as listening stations decode them, bypassing REST polling delays.
* **Instant Sliding-Window Catch-Up:** Automatically fetches historical reports from the PSKReporter REST API for the past 15 to 120 minutes so you never wait with an empty screen.
* **Flashing Live Transmission HUD:** Displays a pulsing neon `TRANSMITTING NOW` banner with subtle audio alert chimes when a transmission is detected within the current 15-second cycle.

### 27.2 FT8 15-Second Cycle Synchronization & Cadence Radar
* **Even vs. Odd Cycle Determination:** Analyzes timestamp seconds (`t_tx % 60`) across spots to classify whether the target station transmits on **Even cycles (:00 / :30)** or **Odd cycles (:15 / :45)**.
* **Real-Time Countdown Ring:** Synchronized circular countdown gauge displaying seconds remaining in the current 15s FT8 slot.
* **Smart Operating Advisory:** Automatically advises the optimal calling cycle (e.g. *"Target transmits on EVEN; Call on ODD (:15 / :45)"*) to eliminate self-interference and guarantee high QSO rates.

### 27.3 360-Degree Polar Radiation Radar
* **Antenna Pattern Visualization:** Plots reporting stations at their exact great-circle bearing azimuth (0° to 360°) and distance (up to 16,000 km) from the target transmitter.
* **SNR Heatmap Coding:** Points are color-coded by reception strength: Green for positive SNR, Cyan for -1 to -10 dB, Orange for -11 to -18 dB, and Purple for weak signals (<-18 dB).
* **Interactive Inspection:** Hovering or clicking any spotter displays receiver callsign, country flag, grid locator, signal strength, and distance.

### 27.4 DX Cluster Spot History & Telnet Integration
* **Automated Cluster Query:** Directly queries public DX cluster nodes (e.g. `dxc.w3lpl.net:7373`) using `sh/dx 15 [CALLSIGN]` to retrieve recent cluster spots, frequencies, spotter remarks, and Zulu timestamps.

### 27.5 Station Automation & Cross-Desk Integration
* **1-Click QSY Radio (CAT):** Instantly commands connected transceivers via Hamlib `rigctld`, FLRig, or TCI to tune to the monitored frequency.
* **1-Click Rotator Steering:** Directs your antenna rotator to point directly at the target station's bearing.
* **Quick Log Transfer:** Pre-fills the Quick Log HUD with the target callsign, band, frequency, and mode for effortless logging.
* **Diagnostic Python CLI Runner:** Embedded terminal runner allowing one-click execution of the original `ham_tracker.py` script for verification and terminal output inspection.

### 27.6 Active QSO Partner Detection (Cross-Cycle Frequency Correlation)
* **Possible Partner Inference:** YAAM monitors full-band PSK Reporter activity via MQTT on the active band and mode (e.g. `pskr/filter/v2/15m/FT8/#`) to suggest stations that may be exchanging messages with the target.
* **Cross-Cycle Cadence & Co-Channel Frequency Matching:** Analyzes stations reported within $\pm 45\text{ Hz}$ on complementary/opposite cycle parity (Odd vs. Even). Alternating reports are correlated as candidate partners; the spots do not contain the exchanged message text.
* **Spot Correlation Score:** Computes a ranking from repeated timing and frequency matches. This score cannot confirm message text or a completed QSO.
* **Dedicated Hero Partner HUD Banner:** Prominently displays the detected QSO partner station with country flag, DXCC entity, Maidenhead grid, frequency offset ($\Delta\text{Hz}$), matched exchanges counter, inter-station geodesic distance, and direct path bearing.
* **Partner Actions:** Open WebSDR receive to check decoded messages, inspect a partner in Call Intelligence, or switch the active target (`Switch Tracker`).
* **Live Radar QSO Vector:** Plots a glowing dashed link vector on the 360° Polar Radar between the Target transmitter and the active Partner, complete with a golden diamond node and callsign banner.
* **Partners Stream Tab:** A dedicated ranked list of all correlated partner candidates with exchanges, confidence meters, and context menus.
* **CLI Partner Diagnostic:** Supports executing `python3 ham_tracker.py [CALLSIGN] --partner` with full real-time terminal output in the diagnostic sheet.

### 27.7 WebSDR FT8 Receive
* Choose **WebSDR RX · FT8** at the top of Digital Callsign Monitor for a dedicated full-width view. Reception stays off until you press **Start receive**. The active Yaam station profile supplies the initial callsign, and 20 m FT8 (14.074 MHz) is selected by default. The profile locator is shown; without one the header reads "Locator not set".
* Compatible classic WebSDRs open in the background, tune FT8 USB with a roughly 3 kHz passband, and decode receiver audio without a microphone. The directory has more than 20 receivers, including DF0HTE, Twente, Utah, KFS, Hack Green, NA5B, Maasbree, SO8OO, DK0TE, K3FEF, Bordeaux, Paraibuna, and Poços de Caldas. Site WAV recording is a fallback when continuous audio is unavailable. Other receiver links need System Audio. The receiver picker shows green for a reachable site, red for an unavailable site, and gray while checking. Reachability does not guarantee usable audio or FT8 activity. Only listed FT8 frequencies for the chosen receiver can be selected. If no message decodes after 90 seconds, YAAM suggests checking the receiver or band. **Receivers** lets you select parallel receivers by region without closing as choices change. Large selections use more CPU, memory, and network bandwidth.
* The receiver menu shows country flags. The decoded list defaults to the target callsign, groups messages by receive cycle, colors even and odd groups pale green and blue, and displays cycle times on 00/15/30/45 second boundaries. Consecutive `:15` and `:45` groups are separate odd cycles. Identical messages heard by multiple selected receivers appear once with all receiver names; a majority has a purple highlight. The flag beside the message identifies its transmitting callsign, while flags beside receiver names identify listening sites. The per-signal **dBFS** is estimated audio level, not calibrated RF SNR.
* Automatic WebSDR audio does not use macOS Screen Recording permission. Other receiver links use **System Audio** or a virtual loopback input. System Audio permission is requested only by its explicit button. Reopen Yaam after granting it. Ad-hoc signed development builds may need a new grant after each installation.
* Select **All** to see every decoded FT8 message or the target callsign to filter the list. Messages mentioning the target are highlighted; messages actually addressed to it are labeled separately. PSK Reporter spots remain separate from decoded radio text.
* Yaam estimates the audio phase from decoded FT8 timing. The phase estimate is modulo 15 seconds; FT8 text cannot reveal how many whole cycles a WebSDR stream is delayed.
* Automatic receive scans overlapping 13.5-second windows of continuous audio so both FT8 cycles can be decoded. It keeps browser audio interruptions on the timeline rather than treating short recordings as complete cycles. A fallback WAV is ignored if its audio duration differs substantially from its recording time. Late decodes and cross-receiver time alignment can add to or regroup a cycle after its first display; the cycle header indicates when collection is active.
* When the monitored target matches your active station callsign, clicking a directed message prepares the expected next FT8 reply. Enter an actual local RF report where prompted; WebSDR dBFS cannot supply one. Transmission requires a configured station grid and a standard FT8 band preset dial; retuning clears the prepared reply. For IC-7300MK2 USB or LAN transmission, connect and configure that radio in FT8 Station, verify the own TX parity and audio path, arm TX, and queue the next slot explicitly. WebSDR timing alone cannot establish the opposite parity because its delay can span whole cycles. The view does not transmit or log automatically.

---

## SKED Directory

Open the **SKED** tab and first choose one of the eight QRZ Rank regions (Middle East, Europe, Asia, Africa, North America, South America, Oceania, or Antarctica). Then choose a country in that region and a ranking category (QSOs, DXCC countries, or band slots). Iran is selected by default. The country picker shows each country's full name, flag, and representative amateur prefix. For the United States, an additional picker offers all US operators or one of the listed states and territories. The regional, country, and state lists come from the QRZ Rank API. YAAM uses your saved token to load up to 19 ranked operators for the selected country or state; if needed, verify and save a replacement token on this page. Click a callsign to see its operator details, ranking, email, and QRZ profile link. Missing addresses are shown as unavailable.

The country or state band strip covers **160m through 6m**. It shows **green** for confirmed contacts, **blue** for logged but unconfirmed contacts, and **orange** for bands with no logged QSO in the active station logbook. State history uses the logbook's `STATE` field. Each operator row separately shows whether that callsign has previous QSOs in your active station logbook, the QSO count, and the bands worked or confirmed with that operator. Historical bands are shown as recorded, including bands outside the SKED planning range. Choose an operator to set the bands you want to request; the directory shows each operator's plan. The suggested bands action fills empty plans with up to three bands not yet worked for that destination. Plans are saved per station, country or state, and callsign. **Select All** selects every operator with a valid email address in the current destination; click **Deselect All** to undo it. When operators are selected, use the shared band controls above the directory to add or remove a band for everyone at once.

Click **Email** for one operator, or select several and click **Email selected**. The email window contains a conversational, editable template and a separate personalized preview for every recipient. Its band controls apply to all selected recipients together. The template is saved automatically, and fields such as `{greeting}`, `{callsign}`, `{bands}`, `{my_grid}`, and `{time_window}` are filled from the operator and active station profile. Enter your name for the signature; each message ends with your name and callsign. The station grid is shortened to four characters. To propose availability, enable **Propose daily availability** and choose the first and last day plus the daily start and end hours in your Mac's local time. The preview and sent email state that you are available during those hours **each day**, converted to UTC; they do not suggest continuous availability across the whole date span. Review the recipients and messages, then send individual emails through the SMTP account configured in YAAM Settings → Email. A station callsign, sender name, valid recipient address, SMTP settings, and at least one requested band per recipient are required. After all messages succeed, the window closes and a confirmation appears. For partial failures, it stays open with progress and retry controls.

Use **Sync QRZ** to refresh contact details, **Copy all emails** to copy available addresses separated by `;`, or **Export CSV** to save an Excel-friendly UTF-8 file. The **Leaderboard → National Standings** view also offers CSV export for the selected country and category.

> **Support & Feedback:**  
> Press `Cmd + Shift + F` anywhere within YAAM to open the feedback panel to submit suggestions, bug reports, or feature requests directly to the development team.
