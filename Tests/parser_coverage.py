#!/usr/bin/env python3
"""
Parser coverage smoke test.

Generates every droneid-go / DragonSync scenario from testscript.py and
cross-references the JSON keys in each payload against the keys the iOS
app's parser actually reads (extracted from XMLParserDelegate.swift,
ZMQHandler.swift, DroneSignatureGenerator.swift).

Outputs:
  - SCENARIO COVERAGE: per-scenario, which keys are read by iOS vs dropped
  - GLOBAL BLIND SPOTS: keys the app reads that no scenario emits (untested
    code paths) and keys scenarios emit that the app never reads (data loss)
  - PER-FIELD ROUTING: which app file reads each key

Run from repo root:
  python3 Tests/parser_coverage.py
"""

import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
APP = REPO / "WarDragon"
PARSER_FILES = [
    APP / "Data Handling" / "Message Parsing" / "XMLParserDelegate.swift",
    APP / "Data Handling" / "RID Network Ingest" / "ZMQHandler.swift",
    APP / "Data Handling" / "Storage" / "DroneSignatureGenerator.swift",
    APP / "Data Handling" / "RID Network Ingest" / "CoTViewModel.swift",
]

sys.path.insert(0, str(REPO / "Tests"))
import testscript


# ---------------------------------------------------------------------
# Step 1: extract every dict subscript / quoted JSON key the iOS app reads
# ---------------------------------------------------------------------

KEY_DICT_PATTERN = re.compile(r'\["([A-Za-z][A-Za-z0-9_/ -]*?)"\]')
KEY_GET_PATTERN = re.compile(r'\.get\(\s*"([A-Za-z][A-Za-z0-9_/ -]*?)"')
HAS_PREFIX_PATTERN = re.compile(r'hasPrefix\(\s*"([A-Za-z][A-Za-z0-9_/ -]*?):"\s*\)')

def extract_ios_keys():
    keys_to_files = {}
    for f in PARSER_FILES:
        text = f.read_text()
        for m in KEY_DICT_PATTERN.finditer(text):
            keys_to_files.setdefault(m.group(1), set()).add(f.name)
        for m in KEY_GET_PATTERN.finditer(text):
            keys_to_files.setdefault(m.group(1), set()).add(f.name)
    return keys_to_files


def extract_ios_remarks_tokens():
    """Tokens parseRemarks (drone path) and applyDroneidGoRemarks recognise."""
    text = (APP / "Data Handling" / "Message Parsing" / "XMLParserDelegate.swift").read_text()
    return sorted({m.group(1) for m in HAS_PREFIX_PATTERN.finditer(text)})


# ---------------------------------------------------------------------
# Step 2: walk a scenario payload, collect every JSON key path
# ---------------------------------------------------------------------

def walk_keys(obj, prefix="", out=None):
    if out is None:
        out = set()
    if isinstance(obj, dict):
        for k, v in obj.items():
            path = f"{prefix}.{k}" if prefix else k
            out.add(k)
            out.add(path)
            walk_keys(v, path, out)
    elif isinstance(obj, list):
        for el in obj:
            walk_keys(el, prefix, out)
    return out


def make_drone(transport):
    cfg = testscript.Config()
    return testscript.DroneSim(
        f"TEST{transport.upper()}{'0'*16}"[:20],
        "AA:BB:CC:DD:EE:FF",
        "Helicopter",
        transport,
        cfg,
    )


SCENARIO_BUILDERS = {
    "wifi": lambda: testscript.scenario_wifi(make_drone("wifi")),
    "ble": lambda: testscript.scenario_ble(make_drone("ble")),
    "uart": lambda: testscript.scenario_uart(make_drone("uart")),
    "dji": lambda: testscript.scenario_dji(make_drone("dji")),
    "area": lambda: testscript.scenario_area(make_drone("wifi")),
    "auth": lambda: testscript.scenario_auth(make_drone("wifi")),
    "caa": lambda: testscript.scenario_caa(make_drone("wifi")),
    "utm": lambda: testscript.scenario_utm(make_drone("wifi")),
    "session": lambda: testscript.scenario_session(make_drone("wifi")),
    "multi": lambda: testscript.scenario_multi([make_drone("ble") for _ in range(3)]),
    "fpv": lambda: testscript.scenario_fpv(make_drone("wifi")),
    "fpv_serial": lambda: testscript.scenario_fpv_serial(make_drone("wifi")),
    "legacy": lambda: testscript.scenario_legacy(make_drone("wifi")),
    "health": lambda: testscript.scenario_health(120),
    "status": lambda: testscript.scenario_status_json(),
    "mqtt_dict": lambda: testscript.mqtt_dict(make_drone("wifi")),
}

REMARKS_BUILDERS = {
    "cot_drone_remarks": lambda: extract_remarks(testscript.cot_drone(make_drone("wifi"))),
    "cot_pilot_remarks": lambda: extract_remarks(testscript.cot_pilot(make_drone("wifi"))),
    "cot_home_remarks": lambda: extract_remarks(testscript.cot_home(make_drone("wifi"))),
    "cot_status_remarks": lambda: extract_remarks(testscript.cot_status()),
}


def extract_remarks(xml_bytes):
    text = xml_bytes.decode("utf-8")
    m = re.search(r"<remarks>(.+?)</remarks>", text, re.DOTALL)
    return m.group(1) if m else ""


# ---------------------------------------------------------------------
# Step 3: report coverage
# ---------------------------------------------------------------------

DOMAIN_KEY_FILTER = re.compile(
    r'^('
    r'Basic ID|BasicID|Basic_ID|Location/Vector Message|Location|System Message|System|'
    r'Self-ID Message|SelfID|Operator ID Message|OperatorID|Auth Message|Frequency Message|'
    r'AUX_ADV_IND|aext|FPV Detection|DroneID|'
    r'id|id_type|MAC|mac|RSSI|rssi|ua_type|protocol_version|transport|frequency_mhz|'
    r'latitude|longitude|geodetic_altitude|speed|vert_speed|height_agl|height_type|'
    r'pressure_altitude|ew_dir_segment|speed_multiplier|op_status|direction|timestamp|'
    r'timestamp_accuracy|status|alt_pressure|horizontal_accuracy|vertical_accuracy|'
    r'horiz_acc|vert_acc|baro_accuracy|baro_acc|speed_accuracy|speed_acc|'
    r'classification_type|classification|operator_lat|operator_lon|operator_altitude_geo|'
    r'operator_alt_geo|operator_id|operator_id_type|operator_location_type|'
    r'home_lat|home_lon|area_count|area_radius|area_floor|area_ceiling|'
    r'text|text_type|description|description_type|name|index|runtime|frequency|'
    r'auth_type|auth_data|page|page_count|length|connected_since|last_message_time|'
    r'connect_attempts|messages_total|messages_per_sec|errors_total|errors_recent|'
    r'last_error|last_error_time|uptime|uptime_ns|state|state_str|enabled|sources|'
    r'serial_number|gps_data|system_stats|memory|disk|temperature|cpu_usage|'
    r'ant_sdr_temps|pluto_temp|zynq_temp|cached|free|used|active|inactive|'
    r'shared|slab|buffers|total|available|track|hae|aa|chan|phy|addr|AdvA|AdvData|'
    r'AdvDataInfo|AdvMode|did|sid|seen_by|observed_at|rid_timestamp'
    r')$'
)


def main():
    ios_keys_map = extract_ios_keys()
    ios_keys = set(k for k in ios_keys_map.keys() if DOMAIN_KEY_FILTER.match(k))
    remarks_tokens = extract_ios_remarks_tokens()

    scenario_keys = {}
    for name, builder in SCENARIO_BUILDERS.items():
        try:
            payload = builder()
        except Exception as exc:
            print(f"[err] scenario {name}: {exc}", file=sys.stderr)
            continue
        all_paths = walk_keys(payload)
        flat_keys = {k for k in all_paths if "." not in k and DOMAIN_KEY_FILTER.match(k)}
        scenario_keys[name] = flat_keys

    remarks_payloads = {n: b() for n, b in REMARKS_BUILDERS.items()}

    union_emitted = set().union(*scenario_keys.values()) if scenario_keys else set()

    # ---- Reports ----
    print("=" * 72)
    print("PARSER COVERAGE — droneid-go / DragonSync scenarios vs iOS app")
    print("=" * 72)

    print("\n[1] PER-SCENARIO KEY COVERAGE")
    print("-" * 72)
    for name, keys in sorted(scenario_keys.items()):
        read = sorted(k for k in keys if k in ios_keys)
        dropped = sorted(k for k in keys if k not in ios_keys)
        print(f"\n  {name}: emits {len(keys)} domain keys, "
              f"iOS reads {len(read)}, drops {len(dropped)}")
        if dropped:
            print(f"    DROPPED (in payload, parser ignores): {dropped}")

    print("\n[2] GLOBAL BLIND SPOTS")
    print("-" * 72)
    only_in_payloads = sorted(union_emitted - ios_keys)
    only_in_parser = sorted(ios_keys - union_emitted)
    print(f"\n  Emitted by scenarios but NOT read by iOS parser ({len(only_in_payloads)}):")
    for k in only_in_payloads:
        print(f"    - {k}")
    print(f"\n  Read by iOS parser but NOT emitted by any scenario ({len(only_in_parser)}):")
    for k in only_in_parser:
        files = sorted(ios_keys_map.get(k, set()))
        print(f"    - {k:<35s} (read by: {', '.join(files) or 'unknown'})")

    print("\n[3] REMARKS-STRING TOKENS RECOGNISED BY parseRemarks/applyDroneidGoRemarks")
    print("-" * 72)
    print(f"  {len(remarks_tokens)} prefix tokens. "
          "Cross-referenced against generated remarks below.")
    remarks_tokens_lower = {t.lower() for t in remarks_tokens}
    for label, remarks in remarks_payloads.items():
        remarks_lower = remarks.lower()
        present = [t for t in remarks_tokens if f"{t.lower()}:" in remarks_lower]
        absent = [t for t in remarks_tokens if f"{t.lower()}:" not in remarks_lower]
        print(f"\n  {label}: matches {len(present)} tokens")
        if label == "cot_drone_remarks":
            unmatched_in_remarks = [
                seg.split(":", 1)[0].strip()
                for seg in re.split(r"[,;]", remarks)
                if ":" in seg
            ]
            unrecognised = sorted({s for s in unmatched_in_remarks
                                   if s and s.lower() not in remarks_tokens_lower
                                   and not s.startswith("Operator Lat")
                                   and not s.startswith("Operator Lon")
                                   and not s.startswith("Home Lat")
                                   and not s.startswith("Home Lon")})
            if unrecognised:
                print(f"    UNRECOGNISED tokens in cot_drone remarks (parser will ignore): "
                      f"{unrecognised}")
        if len(absent) <= 5:
            print(f"    not present: {absent}")

    print("\n[4] PARSER ROUTING — where each domain key is read")
    print("-" * 72)
    for k in sorted(union_emitted | ios_keys):
        if not DOMAIN_KEY_FILTER.match(k):
            continue
        files = sorted(ios_keys_map.get(k, set()))
        emit_status = "✓" if k in union_emitted else " "
        read_status = "✓" if k in ios_keys else " "
        print(f"  [{emit_status}emit/{read_status}read] {k:<32s} {','.join(files) if files else '—'}")


if __name__ == "__main__":
    main()
