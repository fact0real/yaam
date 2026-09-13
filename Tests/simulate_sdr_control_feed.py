#!/usr/bin/env python3
"""
SDR-Control Live Feed & CAT Server Simulator for YAAM
Simulates SDR-Control's real-time WSJT-X UDP decodes broadcast (port 2237)
and Hamlib RigCtrl CAT Server (TCP port 5001).

Usage:
    python3 Tests/simulate_sdr_control_feed.py [--cycles 3] [--delay 2]
"""

import socket
import struct
import sys
import time
import threading
import argparse

# WSJT-X Protocol Constants
WSJTX_MAGIC = 0xADBCCBDA
WSJTX_SCHEMA = 2
WSJTX_TYPE_STATUS = 1
WSJTX_TYPE_DECODE = 2
WSJTX_TYPE_LOG = 12

def encode_qstring(s: str) -> bytes:
    b = s.encode('utf-8')
    return struct.pack('>I', len(b)) + b

def create_wsjtx_status_packet(source_id="SDR-Control", dial_hz=14074000, mode="FT8", dx_call="", report=""):
    buf = bytearray()
    buf.extend(struct.pack('>III', WSJTX_MAGIC, WSJTX_SCHEMA, WSJTX_TYPE_STATUS))
    buf.extend(encode_qstring(source_id))
    buf.extend(struct.pack('>Q', dial_hz))
    buf.extend(encode_qstring(mode))
    buf.extend(encode_qstring(dx_call))
    buf.extend(encode_qstring(report))
    buf.extend(encode_qstring(mode)) # txMode
    buf.extend(struct.pack('>?', False)) # txEnabled
    buf.extend(struct.pack('>?', False)) # transmitting
    buf.extend(struct.pack('>?', True))  # decoding
    buf.extend(struct.pack('>II', 1500, 1500)) # rxDF, txDF
    buf.extend(encode_qstring("EP2DX")) # deCall
    buf.extend(encode_qstring("KM32"))  # deGrid
    buf.extend(encode_qstring(""))      # dxGrid
    buf.extend(struct.pack('>?', False)) # watchdog
    buf.extend(encode_qstring(""))      # subMode
    buf.extend(struct.pack('>?', False)) # fastMode
    buf.extend(struct.pack('>B', 0))    # specialOp
    buf.extend(struct.pack('>II', 50, 15)) # freqTolerance, trPeriod
    buf.extend(encode_qstring("Default")) # configName
    return bytes(buf)

def create_wsjtx_decode_packet(source_id="SDR-Control", is_new=True, time_ms=36000000, snr=-8,
                               dt=0.1, df_hz=1420, mode="~", message="CQ DL1ABC JO31"):
    buf = bytearray()
    buf.extend(struct.pack('>III', WSJTX_MAGIC, WSJTX_SCHEMA, WSJTX_TYPE_DECODE))
    buf.extend(encode_qstring(source_id))
    buf.extend(struct.pack('>?', is_new))
    buf.extend(struct.pack('>I', time_ms))
    buf.extend(struct.pack('>i', snr))
    buf.extend(struct.pack('>d', dt))
    buf.extend(struct.pack('>I', df_hz))
    buf.extend(encode_qstring(mode))
    buf.extend(encode_qstring(message))
    buf.extend(struct.pack('>?', False)) # lowConfidence
    buf.extend(struct.pack('>?', False)) # offAir
    return bytes(buf)

class MockRigCtrlServer:
    def __init__(self, host="127.0.0.1", port=5001):
        self.host = host
        self.port = port
        self.freq_hz = 14074000
        self.mode = "USB"
        self.passband = 3000
        self.ptt = 0
        self.running = True
        self.commands_received = []

    def start(self):
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((self.host, self.port))
            sock.listen(5)
            sock.settimeout(1.0)
            print(f"📡 [Mock SDR-Control RigCtrl] CAT Server listening on TCP {self.host}:{self.port}")
        except Exception as e:
            print(f"⚠️ [Mock RigCtrl] Could not bind TCP {self.port}: {e}")
            return

        while self.running:
            try:
                conn, addr = sock.accept()
            except socket.timeout:
                continue
            except Exception:
                break

            client_thread = threading.Thread(target=self._handle_client, args=(conn, addr), daemon=True)
            client_thread.start()

    def _handle_client(self, conn, addr):
        conn.settimeout(2.0)
        buffer = ""
        while self.running:
            try:
                data = conn.recv(1024)
                if not data:
                    break
                buffer += data.decode('ascii', errors='ignore')
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    line = line.strip()
                    if not line:
                        continue
                    self.commands_received.append(line)
                    response = self._process_command(line)
                    if response:
                        conn.sendall(response.encode('ascii'))
            except socket.timeout:
                continue
            except Exception:
                break
        conn.close()

    def _process_command(self, cmd):
        # rigctld extended protocol handling
        if cmd.startswith("+f") or cmd == "f":
            return f"get_freq:\nFrequency: {self.freq_hz}\nRPRT 0\n"
        elif cmd.startswith("+m") or cmd == "m":
            return f"get_mode:\nMode: {self.mode}\nPassband: {self.passband}\nRPRT 0\n"
        elif cmd.startswith("F ") or cmd.startswith("+F "):
            parts = cmd.split()
            if len(parts) >= 2 and parts[1].isdigit():
                self.freq_hz = int(parts[1])
                print(f"🎛️ [SDR-Control CAT] Frequency tuned to: {self.freq_hz} Hz ({self.freq_hz/1e6:.3f} MHz)")
            return "set_freq:\nRPRT 0\n"
        elif cmd.startswith("M ") or cmd.startswith("+M "):
            parts = cmd.split()
            if len(parts) >= 2:
                self.mode = parts[1]
                if len(parts) >= 3 and parts[2].isdigit():
                    self.passband = int(parts[2])
                print(f"🎛️ [SDR-Control CAT] Mode set to: {self.mode} (PB: {self.passband} Hz)")
            return "set_mode:\nRPRT 0\n"
        elif cmd.startswith("T "):
            parts = cmd.split()
            if len(parts) >= 2:
                self.ptt = int(parts[1])
                print(f"📻 [SDR-Control CAT] PTT State: {'TX ON' if self.ptt else 'TX OFF'}")
            return "set_ptt:\nRPRT 0\n"
        elif cmd == "\\dump_state":
            return "0\n2\n0\n0\nRPRT 0\n"
        return "RPRT 0\n"

def run_simulation(udp_host="127.0.0.1", udp_port=2237, cycles=3, interval_sec=1.5):
    print("=" * 70)
    print("🚀 SDR-Control -> YAAM Live Decode & CAT Simulation Suite")
    print(f"   Target UDP: {udp_host}:{udp_port}")
    print(f"   Mock CAT:   127.0.0.1:5001")
    print("=" * 70)

    # 1. Start mock RigCtrl server
    rig_server = MockRigCtrlServer(port=5001)
    rig_server.start()

    # 2. Setup UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    # Scenarios across cycles
    scenarios = [
        {
            "name": "Cycle 1 (20m Standard Traffic)",
            "band": "20M",
            "dial_hz": 14074000,
            "decodes": [
                ("CQ DL1ABC JO31", "DL1ABC", -6, 1200),
                ("CQ F4KJE IN98", "F4KJE", -12, 1450),
                ("CQ EA3JE JN11", "EA3JE", +3, 1600),
                ("CQ I2ABC JN45", "I2ABC", -4, 1850),
                ("CQ G4XYZ IO91", "G4XYZ", -10, 2100),
            ]
        },
        {
            "name": "Cycle 2 (🌟 ATNO & DIRECT CALL OPPORTUNITY!)",
            "band": "20M",
            "dial_hz": 14074000,
            "decodes": [
                ("CQ 3Y0J KM00", "3Y0J", -8, 1550),         # Bouvet Island (Rare ATNO)
                ("EP2DX 3B8/OE1XXX RR73", "3B8/OE1XXX", -3, 1720), # Direct Caller to Operator!
                ("CQ JA1XYZ PM95", "JA1XYZ", +1, 1340),      # Japan (New Band)
                ("CQ K1ABC FN42", "K1ABC", -14, 1980),       # USA East Coast
            ]
        },
        {
            "name": "Cycle 3 (20m Fading / 15m Propagation Opening)",
            "band": "15M",
            "dial_hz": 21074000,
            "decodes": [
                ("CQ VK4AA QG62", "VK4AA", -4, 1100),
                ("CQ BY1AA OM89", "BY1AA", +5, 1350),
                ("CQ HL2WA PM37", "HL2WA", -2, 1500),
                ("CQ VR2XMT OL72", "VR2XMT", +8, 1650),
                ("CQ 9V1YC OJ11", "9V1YC", -5, 1800),
                ("CQ JA7XYZ QM09", "JA7XYZ", +2, 2050),
            ]
        }
    ]

    total_packets_sent = 0

    for cycle_num, sc in enumerate(scenarios[:cycles], 1):
        print(f"\n📡 Broadcasting {sc['name']} [Band: {sc['band']} - {sc['dial_hz']/1e6:.3f} MHz]...")

        # Send Status Packet
        status_pkt = create_wsjtx_status_packet(
            source_id="SDR-Control",
            dial_hz=sc['dial_hz'],
            mode="FT8"
        )
        sock.sendto(status_pkt, (udp_host, udp_port))
        total_packets_sent += 1

        # Send Decodes
        t_base = 36000000 + cycle_num * 15000
        for msg, caller, snr, df in sc['decodes']:
            dec_pkt = create_wsjtx_decode_packet(
                source_id="SDR-Control",
                is_new=True,
                time_ms=t_base,
                snr=snr,
                dt=0.15,
                df_hz=df,
                mode="~",
                message=msg
            )
            sock.sendto(dec_pkt, (udp_host, udp_port))
            total_packets_sent += 1
            print(f"   -> [{df:4d} Hz] ({snr:+03d} dB) {msg}")
            time.sleep(0.05)

        time.sleep(interval_sec)

    print("\n" + "=" * 70)
    print(f"✅ Simulation finished successfully!")
    print(f"   Total packets sent: {total_packets_sent}")
    print(f"   RigCtrl commands received: {len(rig_server.commands_received)}")
    if rig_server.commands_received:
        print("   Commands log: " + ", ".join(rig_server.commands_received[-5:]))
    print("=" * 70)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Simulate SDR-Control FT8/CAT feed")
    parser.add_argument("--cycles", type=int, default=3, help="Number of simulated 15s decode slots")
    parser.add_argument("--delay", type=float, default=1.0, help="Delay between slots in seconds")
    args = parser.parse_args()
    run_simulation(cycles=args.cycles, interval_sec=args.delay)
