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
Default Station Location (e.g. EP2AES-Home):
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

### 3.4 Real-Time Goertzel DSP Audio Decoder
Connect your transceiver’s headphone or line-out audio to your Mac:
* A tuned **Goertzel Filter** centered at 700 Hz isolates the CW tone from background noise.
* Real-time **Auto-Track WPM** tracks sender speed fluctuations between 10 and 45 WPM, printing decoded text live onto the display.

### 3.5 K1EL WinKeyer Hardware Drivers & Serial Keying
* Native USB serial communication with **K1EL WinKeyer** chipsets (WK2, WK3). Microsecond-precision hardware keying eliminates USB jitter.
* Full support for Iambic A, Iambic B, Ultimatic, and Bug modes.
* Direct DTR/RTS serial line keying support.

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

### 8.5 Sub-Millisecond Master.scp Super Check Partial
As you type callsigns into the contest log, YAAM queries the bundled `Master.scp` database in real time, highlighting known active contest operators to prevent typographical errors.

---

## 9. Operator Desk & Direct Icom MK2 LAN Architecture

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

> **Support & Feedback:**  
> Press `Cmd + Shift + F` anywhere within YAAM to open the feedback panel to submit suggestions, bug reports, or feature requests directly to the development team.
