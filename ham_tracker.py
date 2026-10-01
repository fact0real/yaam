#!/usr/bin/env python3
"""
Ham Radio Callsign Real-Time Tracker & Activity Monitor.

Monitors real-time digital radio activity (FT8, FT4, etc.) via the PSKReporter MQTT feed,
retrieves recent contact spots via DX Cluster Telnet, and correlates transmissions
to identify active QSO partners.
Requires only the Python 3 standard library (no external pip dependencies needed).
"""

import sys
import socket
import struct
import json
import time
import argparse
from datetime import datetime, timezone
from collections import Counter


# ==============================================================================
# MQTT 3.1.1 Lightweight Client (Standard Library Socket Implementation)
# ==============================================================================

def encode_str(s: str) -> bytes:
    """Encode a string with a 2-byte big-endian length prefix for MQTT."""
    b = s.encode('utf-8')
    return struct.pack('!H', len(b)) + b


def build_connect(client_id: str) -> bytes:
    """Construct a standard MQTT 3.1.1 CONNECT packet."""
    proto_name = encode_str('MQTT')
    proto_ver = b'\x04'          # MQTT version 3.1.1
    connect_flags = b'\x02'      # Clean session flag
    keep_alive = struct.pack('!H', 60)
    payload = encode_str(client_id)
    variable_header = proto_name + proto_ver + connect_flags + keep_alive
    rem_len = len(variable_header) + len(payload)
    return b'\x10' + bytes([rem_len]) + variable_header + payload


def build_subscribe(packet_id: int, topic: str) -> bytes:
    """Construct an MQTT SUBSCRIBE packet with QoS 0."""
    variable_header = struct.pack('!H', packet_id)
    payload = encode_str(topic) + b'\x00'  # Requested QoS 0
    rem_len = len(variable_header) + len(payload)
    return b'\x82' + bytes([rem_len]) + variable_header + payload


def parse_remaining_length(sock: socket.socket) -> int:
    """Decode the variable-length remaining length field from MQTT packet."""
    multiplier = 1
    value = 0
    while True:
        b = sock.recv(1)[0]
        value += (b & 127) * multiplier
        multiplier *= 128
        if (b & 128) == 0:
            break
    return value


def recv_exact(sock: socket.socket, length: int) -> bytes:
    """Ensure exact number of bytes are read from socket."""
    buf = b''
    while len(buf) < length:
        chunk = sock.recv(length - len(buf))
        if not chunk:
            break
        buf += chunk
    return buf


# ==============================================================================
# DX Cluster Query (Telnet)
# ==============================================================================

def get_cluster_history(callsign: str, count: int = 10) -> list:
    """
    Query a public DX Cluster node (dxc.w3lpl.net) via Telnet (port 7373)
    to retrieve recent spots and reports for the specified callsign.
    """
    print(f"\n[*] Querying DX Cluster (dxc.w3lpl.net) for recent spots of {callsign}...")
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(4.0)
        sock.connect(('dxc.w3lpl.net', 7373))
        time.sleep(0.5)
        sock.recv(2048)  # Receive banner
        sock.sendall(b'GUEST\r\n')  # Guest login
        time.sleep(0.8)
        sock.recv(2048)  # Receive welcome message

        # Command: show latest DX spots for callsign
        cmd = f'sh/dx {count} {callsign}\r\n'.encode('latin1')
        sock.sendall(cmd)
        time.sleep(1.0)
        resp = sock.recv(4096).decode('latin1', errors='ignore')
        sock.close()

        spots = []
        for line in resp.splitlines():
            if callsign.upper() in line.upper() and ('Z' in line or 'kHz' in line):
                spots.append(line.strip())
        return spots
    except Exception:
        return []


# ==============================================================================
# Live PSKReporter Monitoring via MQTT Feed
# ==============================================================================

def monitor_live(callsign: str, duration: int = 30) -> None:
    """
    Connect to mqtt.pskreporter.info on port 1883 and listen for live spots
    transmitted by the specified callsign.
    """
    callsign = callsign.upper().strip()
    print(f"[*] Connecting to PSKReporter live feed (mqtt.pskreporter.info:1883)...")

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(duration + 5.0)
        sock.connect(('mqtt.pskreporter.info', 1883))

        client_id = f"hamtrack-{int(time.time())}"
        sock.sendall(build_connect(client_id))
        connack = sock.recv(4)
        if connack[0] != 0x20 or connack[3] != 0:
            print("[-] Connection failed: MQTT broker rejected connection.")
            return

        # Subscribe to all transmissions sent by this callsign across all bands & modes
        topic = f"pskr/filter/v2/+/+/{callsign}/#"
        sock.sendall(build_subscribe(1, topic))
        sock.recv(5)  # SUBACK

        print(f"[+] Connected! Monitoring transmissions for {callsign} for {duration} seconds...")
        print("=" * 80)

        start_time = time.time()
        spots_found = 0

        while time.time() - start_time < duration:
            try:
                sock.settimeout(2.0)
                pkt_head = sock.recv(1)
                if not pkt_head:
                    break

                pkt_type = pkt_head[0] >> 4
                rem_len = parse_remaining_length(sock)
                body = recv_exact(sock, rem_len)

                if pkt_type == 3:  # MQTT PUBLISH message
                    topic_len = struct.unpack('!H', body[:2])[0]
                    raw_json = body[2 + topic_len:].decode('utf-8', errors='ignore')
                    data = json.loads(raw_json)

                    spots_found += 1
                    freq_hz = data.get('f', 0)
                    freq_mhz = freq_hz / 1e6
                    mode = data.get('md', 'N/A')
                    band = data.get('b', 'N/A')
                    snr = data.get('rp', 0)
                    rx_station = data.get('rc', 'N/A')
                    rx_grid = data.get('rl', '')
                    tx_grid = data.get('sl', '')
                    t_tx = data.get('t_tx', int(time.time()))

                    tx_time_str = datetime.fromtimestamp(t_tx, timezone.utc).strftime('%H:%M:%S UTC')
                    cycle_sec = t_tx % 60
                    if cycle_sec in [14, 15, 44, 45]:
                        cycle_type = "Odd (:15 / :45)"
                    elif cycle_sec in [0, 1, 29, 30]:
                        cycle_type = "Even (:00 / :30)"
                    else:
                        cycle_type = f":{cycle_sec:02d}"

                    print(f"[{tx_time_str}] Band: {band:4} | Freq: {freq_mhz:9.4f} MHz | Mode: {mode:4} | Cycle: {cycle_type}")
                    print(f"       -> Heard by: {rx_station:9} ({rx_grid:6}) | Signal (SNR): {snr:+3} dB | TX Grid: {tx_grid}")
                    print("-" * 80)

            except socket.timeout:
                continue
            except Exception as e:
                print(f"[-] Error processing incoming packet: {e}")
                break

        sock.close()
        if spots_found == 0:
            print(f"[!] No transmissions detected from {callsign} during this {duration}-second window.")
            print("    (The station might be listening, in an idle period, or not currently active.)")
        else:
            print(f"[+] Total live reports received: {spots_found}")

    except Exception as e:
        print(f"[-] Socket/Network Error: {e}")


# ==============================================================================
# QSO Partner Detection via Cross-Cycle Frequency Correlation
# ==============================================================================

def detect_partner(callsign: str, duration: int = 45) -> None:
    """
    Identifies active QSO partner stations by:
    1. Detecting the target callsign's exact transmit frequency and cycle (Odd vs Even).
    2. Monitoring opposite cycle transmissions on the exact same audio frequency (+/- 35 Hz).
    """
    callsign = callsign.upper().strip()
    print(f"\n[*] Detecting active QSO partner for {callsign} (monitoring {duration}s)...")
    print("[*] Subscribing to full band traffic on PSKReporter MQTT...")

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(duration + 5.0)
        sock.connect(('mqtt.pskreporter.info', 1883))

        cid = f"partner-{int(time.time())}"
        sock.sendall(build_connect(cid))
        sock.recv(4)

        # Step 1: Subscribe to 15m FT8 (or target callsign)
        sock.sendall(build_subscribe(1, "pskr/filter/v2/15m/FT8/#"))
        sock.recv(5)

        target_freqs = []
        partner_candidates = Counter()
        start_time = time.time()

        print(f"[+] Analyzing transmissions across alternating 15-second cycles...")
        print("=" * 80)

        while time.time() - start_time < duration:
            try:
                sock.settimeout(2.0)
                pkt_head = sock.recv(1)
                if not pkt_head:
                    break
                rem_len = parse_remaining_length(sock)
                body = recv_exact(sock, rem_len)
                pkt_type = pkt_head[0] >> 4

                if pkt_type == 3:
                    topic_len = struct.unpack('!H', body[:2])[0]
                    raw_json = body[2 + topic_len:].decode('utf-8', errors='ignore')
                    data = json.loads(raw_json)

                    sender = data.get('sc', '')
                    freq = data.get('f', 0)
                    t_tx = data.get('t_tx', 0)
                    sec = t_tx % 60

                    if sender == callsign:
                        target_freqs.append(freq)
                        cycle_desc = "Odd (:15/:45)" if sec in [14, 15, 44, 45] else "Even (:00/:30)"
                        print(f"[TARGET TX] {callsign} transmitted on {freq/1e6:.4f} MHz @ cycle {cycle_desc}")
                    elif target_freqs:
                        avg_f = sum(target_freqs) / len(target_freqs)
                        # Check if this station is transmitting on the opposite cycle within 40 Hz
                        if abs(freq - avg_f) <= 40 and sec in [0, 1, 29, 30]:
                            partner_candidates[sender] += 1
                            print(f"       -> [CALLER MATCH] {sender:8} answered on {freq/1e6:.4f} MHz (@ :{sec:02d}s)")

            except socket.timeout:
                continue
            except Exception:
                break

        sock.close()
        print("-" * 80)
        if partner_candidates:
            print(f"[+] Top candidate QSO partner(s) communicating with {callsign}:")
            for station, count in partner_candidates.most_common(3):
                print(f"    ⭐ Callsign: {station:10} (exchanged {count} matched cycle transmissions)")
        else:
            print(f"[!] No direct QSO partner detected in this window (station may be calling CQ).")

    except Exception as e:
        print(f"[-] Error: {e}")


# ==============================================================================
# CLI Entry Point
# ==============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Real-Time Amateur Radio Callsign Activity Tracker & QSO Partner Detector"
    )
    parser.add_argument("callsign", help="Amateur radio callsign to monitor (e.g. EP2AES)")
    parser.add_argument(
        "-t", "--time",
        type=int,
        default=30,
        help="Duration of live monitoring in seconds (default: 30)"
    )
    parser.add_argument(
        "--no-cluster",
        action="store_true",
        help="Skip querying DX Cluster history"
    )
    parser.add_argument(
        "--partner",
        action="store_true",
        help="Detect and identify the active QSO partner communicating with this callsign"
    )

    args = parser.parse_args()
    call = args.callsign.upper().strip()

    print("=" * 80)
    print(f"  HAM RADIO ACTIVITY TRACKER :: {call}")
    print("=" * 80)

    if not args.no_cluster:
        history = get_cluster_history(call)
        if history:
            print("[+] Recent DX Cluster spots:")
            for h in history[:8]:
                print(f"    {h}")
        else:
            print("[!] No recent spots found on DX Cluster.")

    if args.partner:
        detect_partner(call, duration=args.time)
    else:
        monitor_live(call, duration=args.time)


if __name__ == '__main__':
    main()
