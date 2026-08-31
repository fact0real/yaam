//
//  CountryFlagEngine.swift
//  YAAM
//

import Foundation

// MARK: - Comprehensive DXCC & Country/Territory Flag Lookup Engine

nonisolated func flagFromCallsignPrefix(_ callsign: String) -> String? {
    let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !clean.isEmpty else { return nil }
    
    // 1. High-priority Special DXCC Island & Sub-entity Prefixes
    if clean.hasPrefix("RI1F") { return "🇷🇺" } // Franz Josef Land
    if clean.hasPrefix("RI1A") || clean.hasPrefix("DP0") || clean.hasPrefix("DP1") || clean.hasPrefix("CE9") || clean.hasPrefix("LU/Z") || clean.hasPrefix("KC4AAA") || clean.hasPrefix("KC4US") || clean.hasPrefix("8J1R") || clean.hasPrefix("ZS7") { return "🇦🇶" } // Antarctica
    if clean.hasPrefix("HK0/A") || clean.hasPrefix("HK0/S") || clean.hasPrefix("HK0R") || clean.hasPrefix("HK0NA") { return "🇨🇴" } // San Andres
    if clean.hasPrefix("HK0M") { return "🇨🇴" } // Malpelo
    if clean.hasPrefix("TI9") { return "🇨🇷" } // Cocos Is.
    if clean.hasPrefix("XF4") { return "🇲🇽" } // Revillagigedo
    if clean.hasPrefix("FO/M") || clean.hasPrefix("TX7") { return "🇵🇫" } // Marquesas / Austral
    if clean.hasPrefix("VP6D") || clean.hasPrefix("VP6A") { return "🇵🇳" } // Ducie / Pitcairn
    if clean.hasPrefix("3Y/B") || clean.hasPrefix("3Y0B") { return "🇧🇻" } // Bouvet
    if clean.hasPrefix("3Y/P") || clean.hasPrefix("3Y0P") { return "🇦🇶" } // Peter 1
    if clean.hasPrefix("VK0H") { return "🇭🇲" } // Heard Is.
    if clean.hasPrefix("VK0M") { return "🇦🇺" } // Macquarie Is.
    if clean.hasPrefix("VK9N") { return "🇳🇫" } // Norfolk Is.
    if clean.hasPrefix("VK9C") { return "🇨🇨" } // Cocos Keeling
    if clean.hasPrefix("VK9X") { return "🇨🇽" } // Christmas Is.
    if clean.hasPrefix("VK9L") { return "🇦🇺" } // Lord Howe
    if clean.hasPrefix("VK9M") { return "🇦🇺" } // Mellish Reef
    if clean.hasPrefix("VK9W") { return "🇦🇺" } // Willis Is.
    if clean.hasPrefix("ZL7") { return "🇳🇿" } // Chatham
    if clean.hasPrefix("ZL8") { return "🇳🇿" } // Kermadec
    if clean.hasPrefix("ZL9") { return "🇳🇿" } // Auckland & Campbell
    if clean.hasPrefix("3D2R") { return "🇫🇯" } // Rotuma
    if clean.hasPrefix("3D2C") { return "🇫🇯" } // Conway Reef
    if clean.hasPrefix("OJ0") { return "🇫🇮" } // Market Reef
    if clean.hasPrefix("SV/A") { return "🇬🇷" } // Mount Athos
    if clean.hasPrefix("SV5") { return "🇬🇷" } // Dodecanese
    if clean.hasPrefix("SV9") { return "🇬🇷" } // Crete
    if clean.hasPrefix("1A0") { return "🇲🇹" } // SMOM
    if clean.hasPrefix("4U1UN") || clean.hasPrefix("4U1ITU") || clean.hasPrefix("4U1VIC") { return "🇺🇳" } // UN
    if clean.hasPrefix("BS7H") { return "🇵🇭" } // Scarborough
    if clean.hasPrefix("BV9P") { return "🇹🇼" } // Pratas
    if clean.hasPrefix("JD1") { return "🇯🇵" } // Ogasawara / Minami Torishima
    if clean.hasPrefix("7O") { return "🇾🇪" } // Yemen / Socotra
    if clean.hasPrefix("PY0F") { return "🇧🇷" } // Fernando de Noronha
    if clean.hasPrefix("PY0S") { return "🇧🇷" } // St. Peter & Paul
    if clean.hasPrefix("PY0T") { return "🇧🇷" } // Trindade
    if clean.hasPrefix("YV0") { return "🇻🇪" } // Aves Is.
    if clean.hasPrefix("FT/W") || clean.hasPrefix("FT/X") || clean.hasPrefix("FT/Z") || clean.hasPrefix("FT/T") { return "🇹🇫" }
    if clean.hasPrefix("ZD7") || clean.hasPrefix("ZD8") || clean.hasPrefix("ZD9") { return "🇸🇭" }
    if clean.hasPrefix("VP8") { return "🇫🇰" }
    if clean.hasPrefix("VP2M") { return "🇲🇸" }
    if clean.hasPrefix("VP2E") { return "🇦🇮" }
    if clean.hasPrefix("VP2V") { return "🇻🇬" }
    if clean.hasPrefix("VP5") { return "🇹🇨" }
    if clean.hasPrefix("ZF") { return "🇰🇾" }
    if clean.hasPrefix("V4") { return "🇰🇳" }
    if clean.hasPrefix("J6") { return "🇱🇨" }
    if clean.hasPrefix("J8") { return "🇻🇨" }
    if clean.hasPrefix("J3") { return "🇬🇩" }
    if clean.hasPrefix("J7") { return "🇩🇲" }
    if clean.hasPrefix("8P") { return "🇧🇧" }
    if clean.hasPrefix("9Y") { return "🇹🇹" }
    if clean.hasPrefix("PJ2") { return "🇨🇼" }
    if clean.hasPrefix("PJ4") { return "🇧🇶" }
    if clean.hasPrefix("PJ7") { return "🇸🇽" }
    if clean.hasPrefix("P4") { return "🇦🇼" }
    if clean.hasPrefix("KH6") || clean.hasPrefix("AH6") || clean.hasPrefix("NH6") || clean.hasPrefix("WH6") { return "🇺🇸" } // Hawaii
    if clean.hasPrefix("KL7") || clean.hasPrefix("AL7") || clean.hasPrefix("NL7") || clean.hasPrefix("WL7") || clean.hasPrefix("NL8") || clean.hasPrefix("KL8") || clean.hasPrefix("AL8") { return "🇺🇸" } // Alaska
    if clean.hasPrefix("KP4") || clean.hasPrefix("WP4") || clean.hasPrefix("NP4") { return "🇵🇷" } // Puerto Rico
    if clean.hasPrefix("KP2") || clean.hasPrefix("WP2") || clean.hasPrefix("NP2") { return "🇻🇮" } // US Virgin Is
    if clean.hasPrefix("KH2") || clean.hasPrefix("AH2") || clean.hasPrefix("NH2") || clean.hasPrefix("WH2") { return "🇬🇺" } // Guam
    if clean.hasPrefix("KH0") || clean.hasPrefix("AH0") || clean.hasPrefix("NH0") || clean.hasPrefix("WH0") { return "🇲🇵" } // Saipan
    if clean.hasPrefix("KH8") || clean.hasPrefix("AH8") || clean.hasPrefix("NH8") || clean.hasPrefix("WH8") { return "🇦🇸" } // American Samoa
    if clean.hasPrefix("OH0") { return "🇦🇽" } // Aland Is
    if clean.hasPrefix("JW") || clean.hasPrefix("JX") { return "🇸🇯" } // Svalbard / Jan Mayen
    if clean.hasPrefix("OY") { return "🇫🇴" } // Faroe
    if clean.hasPrefix("OX") { return "🇬🇱" } // Greenland

    // 2. Standard Global ITU Prefixes
    if clean.hasPrefix("C9") { return "🇲🇿" }
    if clean.hasPrefix("P2") { return "🇵🇬" }
    if clean.hasPrefix("5N") { return "🇳🇬" }
    if clean.hasPrefix("Z2") { return "🇿🇼" }
    if clean.hasPrefix("9N") { return "🇳🇵" }
    if clean.hasPrefix("XE") || clean.hasPrefix("XF") || clean.hasPrefix("4A") || clean.hasPrefix("4B") || clean.hasPrefix("4C") || clean.hasPrefix("6D") || clean.hasPrefix("6E") || clean.hasPrefix("6F") || clean.hasPrefix("6G") || clean.hasPrefix("6H") || clean.hasPrefix("6I") || clean.hasPrefix("6J") { return "🇲🇽" }
    if clean.hasPrefix("HI") { return "🇩🇴" }
    if clean.hasPrefix("HK") || clean.hasPrefix("HJ") || clean.hasPrefix("5J") || clean.hasPrefix("5K") { return "🇨🇴" }
    if clean.hasPrefix("EP") || clean.hasPrefix("EQ") || clean.hasPrefix("9D") { return "🇮🇷" }
    if clean.hasPrefix("JA") || clean.hasPrefix("JE") || clean.hasPrefix("JF") || clean.hasPrefix("JG") || clean.hasPrefix("JH") || clean.hasPrefix("JI") || clean.hasPrefix("JJ") || clean.hasPrefix("JK") || clean.hasPrefix("JL") || clean.hasPrefix("JM") || clean.hasPrefix("JN") || clean.hasPrefix("JO") || clean.hasPrefix("JP") || clean.hasPrefix("JQ") || clean.hasPrefix("JR") || clean.hasPrefix("JS") || clean.hasPrefix("7J") || clean.hasPrefix("7K") || clean.hasPrefix("7L") || clean.hasPrefix("7M") || clean.hasPrefix("7N") || clean.hasPrefix("8J") || clean.hasPrefix("8K") || clean.hasPrefix("8L") || clean.hasPrefix("8M") || clean.hasPrefix("8N") { return "🇯🇵" }
    if clean.hasPrefix("BY") || clean.hasPrefix("BA") || clean.hasPrefix("BD") || clean.hasPrefix("BG") || clean.hasPrefix("BH") || clean.hasPrefix("BI") || clean.hasPrefix("BJ") || clean.hasPrefix("BL") || clean.hasPrefix("BT") || clean.hasPrefix("BV") { return "🇨🇳" }
    if clean.hasPrefix("DL") || clean.hasPrefix("DK") || clean.hasPrefix("DJ") || clean.hasPrefix("DF") || clean.hasPrefix("DG") || clean.hasPrefix("DH") || clean.hasPrefix("DB") || clean.hasPrefix("DC") || clean.hasPrefix("DD") || clean.hasPrefix("DM") || clean.hasPrefix("DO") || clean.hasPrefix("DP") || clean.hasPrefix("DQ") || clean.hasPrefix("DR") { return "🇩🇪" }
    if clean.hasPrefix("F") || clean.hasPrefix("TM") || clean.hasPrefix("TK") { return "🇫🇷" }
    if clean.hasPrefix("EA") || clean.hasPrefix("EB") || clean.hasPrefix("EC") || clean.hasPrefix("ED") || clean.hasPrefix("EE") || clean.hasPrefix("EF") || clean.hasPrefix("EG") || clean.hasPrefix("EH") || clean.hasPrefix("AM") || clean.hasPrefix("AN") || clean.hasPrefix("AO") { return "🇪🇸" }
    if clean.hasPrefix("CT") || clean.hasPrefix("CQ") || clean.hasPrefix("CR") || clean.hasPrefix("CS") || clean.hasPrefix("CU") { return "🇵🇹" }
    if clean.hasPrefix("I") || clean.hasPrefix("IK") || clean.hasPrefix("IZ") || clean.hasPrefix("IU") || clean.hasPrefix("IQ") || clean.hasPrefix("IT") || clean.hasPrefix("IS") || clean.hasPrefix("IW") || clean.hasPrefix("IA") || clean.hasPrefix("IB") || clean.hasPrefix("IC") || clean.hasPrefix("ID") || clean.hasPrefix("IE") || clean.hasPrefix("IF") || clean.hasPrefix("IG") || clean.hasPrefix("IH") || clean.hasPrefix("II") || clean.hasPrefix("IJ") || clean.hasPrefix("IL") || clean.hasPrefix("IN") || clean.hasPrefix("IO") || clean.hasPrefix("IP") || clean.hasPrefix("IR") { return "🇮🇹" }
    if clean.hasPrefix("G") || clean.hasPrefix("M") || clean.hasPrefix("2E") || clean.hasPrefix("2M") || clean.hasPrefix("2W") || clean.hasPrefix("2I") || clean.hasPrefix("2D") || clean.hasPrefix("2J") || clean.hasPrefix("2U") || clean.hasPrefix("GX") || clean.hasPrefix("MX") { return "🇬🇧" }
    if clean.hasPrefix("GM") || clean.hasPrefix("MM") || clean.hasPrefix("GS") || clean.hasPrefix("MS") { return "🏴󠁧󠁢󠁳󠁣󠁴󠁿" }
    if clean.hasPrefix("GW") || clean.hasPrefix("MW") || clean.hasPrefix("GC") || clean.hasPrefix("MC") { return "🏴󠁧󠁢󠁷󠁬󠁳󠁿" }
    if clean.hasPrefix("GI") || clean.hasPrefix("MI") || clean.hasPrefix("GN") || clean.hasPrefix("MN") { return "🇬🇧" }
    if clean.hasPrefix("GD") || clean.hasPrefix("MD") || clean.hasPrefix("GT") || clean.hasPrefix("MT") { return "🇮🇲" }
    if clean.hasPrefix("GJ") || clean.hasPrefix("MJ") || clean.hasPrefix("GH") || clean.hasPrefix("MH") { return "🇯🇪" }
    if clean.hasPrefix("GU") || clean.hasPrefix("MU") || clean.hasPrefix("GP") || clean.hasPrefix("MP") { return "🇬🇬" }
    if clean.hasPrefix("ZB") || clean.hasPrefix("ZG") { return "🇬🇮" }
    if clean.hasPrefix("UA") || clean.hasPrefix("UB") || clean.hasPrefix("UC") || clean.hasPrefix("UD") || clean.hasPrefix("UF") || clean.hasPrefix("UG") || clean.hasPrefix("UH") || clean.hasPrefix("UI") || clean.hasPrefix("RA") || clean.hasPrefix("RB") || clean.hasPrefix("RC") || clean.hasPrefix("RD") || clean.hasPrefix("RE") || clean.hasPrefix("RF") || clean.hasPrefix("RG") || clean.hasPrefix("RH") || clean.hasPrefix("RI") || clean.hasPrefix("RJ") || clean.hasPrefix("RK") || clean.hasPrefix("RL") || clean.hasPrefix("RM") || clean.hasPrefix("RN") || clean.hasPrefix("RO") || clean.hasPrefix("RP") || clean.hasPrefix("RQ") || clean.hasPrefix("RR") || clean.hasPrefix("RS") || clean.hasPrefix("RT") || clean.hasPrefix("RU") || clean.hasPrefix("RV") || clean.hasPrefix("RW") || clean.hasPrefix("RX") || clean.hasPrefix("RY") || clean.hasPrefix("RZ") || clean.hasPrefix("R0") || clean.hasPrefix("R1") || clean.hasPrefix("R2") || clean.hasPrefix("R3") || clean.hasPrefix("R4") || clean.hasPrefix("R5") || clean.hasPrefix("R6") || clean.hasPrefix("R7") || clean.hasPrefix("R8") || clean.hasPrefix("R9") || clean.hasPrefix("UA2") { return "🇷🇺" }
    if clean.hasPrefix("UR") || clean.hasPrefix("US") || clean.hasPrefix("UT") || clean.hasPrefix("UU") || clean.hasPrefix("UV") || clean.hasPrefix("UW") || clean.hasPrefix("UX") || clean.hasPrefix("UY") || clean.hasPrefix("UZ") || clean.hasPrefix("EM") || clean.hasPrefix("EN") || clean.hasPrefix("EO") { return "🇺🇦" }
    if clean.hasPrefix("EU") || clean.hasPrefix("EV") || clean.hasPrefix("EW") { return "🇧🇾" }
    if clean.hasPrefix("SP") || clean.hasPrefix("SQ") || clean.hasPrefix("SN") || clean.hasPrefix("SO") || clean.hasPrefix("3Z") || clean.hasPrefix("HF") { return "🇵🇱" }
    if clean.hasPrefix("OK") || clean.hasPrefix("OL") { return "🇨🇿" }
    if clean.hasPrefix("OM") { return "🇸🇰" }
    if clean.hasPrefix("HA") || clean.hasPrefix("HG") { return "🇭🇺" }
    if clean.hasPrefix("OE") { return "🇦🇹" }
    if clean.hasPrefix("HB") || clean.hasPrefix("HE") { return "🇨🇭" }
    if clean.hasPrefix("HB0") { return "🇱🇮" }
    if clean.hasPrefix("PA") || clean.hasPrefix("PB") || clean.hasPrefix("PC") || clean.hasPrefix("PD") || clean.hasPrefix("PE") || clean.hasPrefix("PF") || clean.hasPrefix("PG") || clean.hasPrefix("PH") || clean.hasPrefix("PI") { return "🇳🇱" }
    if clean.hasPrefix("ON") || clean.hasPrefix("OO") || clean.hasPrefix("OP") || clean.hasPrefix("OQ") || clean.hasPrefix("OR") || clean.hasPrefix("OS") || clean.hasPrefix("OT") { return "🇧🇪" }
    if clean.hasPrefix("LX") { return "🇱🇺" }
    if clean.hasPrefix("SM") || clean.hasPrefix("SA") || clean.hasPrefix("SB") || clean.hasPrefix("SC") || clean.hasPrefix("SD") || clean.hasPrefix("SE") || clean.hasPrefix("SF") || clean.hasPrefix("SG") || clean.hasPrefix("SH") || clean.hasPrefix("SI") || clean.hasPrefix("SJ") || clean.hasPrefix("SK") || clean.hasPrefix("SL") || clean.hasPrefix("7S") || clean.hasPrefix("8S") { return "🇸🇪" }
    if clean.hasPrefix("LA") || clean.hasPrefix("LB") || clean.hasPrefix("LC") || clean.hasPrefix("LD") || clean.hasPrefix("LE") || clean.hasPrefix("LF") || clean.hasPrefix("LG") || clean.hasPrefix("LH") || clean.hasPrefix("LI") || clean.hasPrefix("LJ") || clean.hasPrefix("LN") { return "🇳🇴" }
    if clean.hasPrefix("OH") || clean.hasPrefix("OF") || clean.hasPrefix("OG") || clean.hasPrefix("OI") { return "🇫🇮" }
    if clean.hasPrefix("OZ") || clean.hasPrefix("OU") || clean.hasPrefix("OV") || clean.hasPrefix("5P") || clean.hasPrefix("5Q") { return "🇩🇰" }
    if clean.hasPrefix("TF") { return "🇮🇸" }
    if clean.hasPrefix("EI") || clean.hasPrefix("EJ") { return "🇮🇪" }
    if clean.hasPrefix("SV") || clean.hasPrefix("SX") || clean.hasPrefix("SY") || clean.hasPrefix("SZ") || clean.hasPrefix("J4") { return "🇬🇷" }
    if clean.hasPrefix("YO") || clean.hasPrefix("YP") || clean.hasPrefix("YQ") || clean.hasPrefix("YR") { return "🇷🇴" }
    if clean.hasPrefix("LZ") { return "🇧🇬" }
    if clean.hasPrefix("9A") { return "🇭🇷" }
    if clean.hasPrefix("S5") { return "🇸🇮" }
    if clean.hasPrefix("YU") || clean.hasPrefix("YT") || clean.hasPrefix("YZ") { return "🇷🇸" }
    if clean.hasPrefix("E7") { return "🇧🇦" }
    if clean.hasPrefix("Z3") { return "🇲🇰" }
    if clean.hasPrefix("4O") { return "🇲🇪" }
    if clean.hasPrefix("ZA") { return "🇦🇱" }
    if clean.hasPrefix("Z6") { return "🇽🇰" }
    if clean.hasPrefix("ER") { return "🇲🇩" }
    if clean.hasPrefix("ES") { return "🇪🇪" }
    if clean.hasPrefix("YL") { return "🇱🇻" }
    if clean.hasPrefix("LY") { return "🇱🇹" }
    if clean.hasPrefix("5B") || clean.hasPrefix("C4") || clean.hasPrefix("P3") || clean.hasPrefix("H2") { return "🇨🇾" }
    if clean.hasPrefix("9H") { return "🇲🇹" }
    if clean.hasPrefix("3A") { return "🇲🇨" }
    if clean.hasPrefix("C3") { return "🇦🇩" }
    if clean.hasPrefix("T7") { return "🇸🇲" }
    if clean.hasPrefix("HV") { return "🇻🇦" }
    if clean.hasPrefix("W") || clean.hasPrefix("K") || clean.hasPrefix("N") || clean.hasPrefix("AA") || clean.hasPrefix("AB") || clean.hasPrefix("AC") || clean.hasPrefix("AD") || clean.hasPrefix("AE") || clean.hasPrefix("AF") || clean.hasPrefix("AG") || clean.hasPrefix("AH") || clean.hasPrefix("AI") || clean.hasPrefix("AJ") || clean.hasPrefix("AK") { return "🇺🇸" }
    if clean.hasPrefix("VE") || clean.hasPrefix("VA") || clean.hasPrefix("VO") || clean.hasPrefix("VY") || clean.hasPrefix("CF") || clean.hasPrefix("CG") || clean.hasPrefix("CJ") || clean.hasPrefix("CK") || clean.hasPrefix("CY") || clean.hasPrefix("CZ") || clean.hasPrefix("VC") || clean.hasPrefix("VD") || clean.hasPrefix("VG") || clean.hasPrefix("VX") || clean.hasPrefix("XJ") || clean.hasPrefix("XK") || clean.hasPrefix("XL") || clean.hasPrefix("XM") || clean.hasPrefix("XN") || clean.hasPrefix("XO") { return "🇨🇦" }
    if clean.hasPrefix("VK") || clean.hasPrefix("AX") || clean.hasPrefix("VI") || clean.hasPrefix("VJ") || clean.hasPrefix("VL") || clean.hasPrefix("VM") || clean.hasPrefix("VN") || clean.hasPrefix("VZ") { return "🇦🇺" }
    if clean.hasPrefix("ZL") || clean.hasPrefix("ZM") { return "🇳🇿" }
    if clean.hasPrefix("LU") || clean.hasPrefix("LW") || clean.hasPrefix("LV") || clean.hasPrefix("AY") || clean.hasPrefix("AZ") || clean.hasPrefix("L1") || clean.hasPrefix("L2") || clean.hasPrefix("L3") || clean.hasPrefix("L4") || clean.hasPrefix("L5") || clean.hasPrefix("L6") || clean.hasPrefix("L7") || clean.hasPrefix("L8") || clean.hasPrefix("L9") { return "🇦🇷" }
    if clean.hasPrefix("PY") || clean.hasPrefix("PP") || clean.hasPrefix("PQ") || clean.hasPrefix("PR") || clean.hasPrefix("PS") || clean.hasPrefix("PT") || clean.hasPrefix("PU") || clean.hasPrefix("PV") || clean.hasPrefix("PW") || clean.hasPrefix("PX") || clean.hasPrefix("ZV") || clean.hasPrefix("ZW") || clean.hasPrefix("ZX") || clean.hasPrefix("ZY") || clean.hasPrefix("ZZ") { return "🇧🇷" }
    if clean.hasPrefix("CE") || clean.hasPrefix("CA") || clean.hasPrefix("CB") || clean.hasPrefix("CC") || clean.hasPrefix("CD") || clean.hasPrefix("XQ") || clean.hasPrefix("XR") || clean.hasPrefix("3G") { return "🇨🇱" }
    if clean.hasPrefix("OA") || clean.hasPrefix("OB") || clean.hasPrefix("OC") || clean.hasPrefix("4T") { return "🇵🇪" }
    if clean.hasPrefix("HC") || clean.hasPrefix("HD") { return "🇪🇨" }
    if clean.hasPrefix("YV") || clean.hasPrefix("YY") || clean.hasPrefix("YW") || clean.hasPrefix("4M") { return "🇻🇪" }
    if clean.hasPrefix("ZP") { return "🇵🇾" }
    if clean.hasPrefix("CX") || clean.hasPrefix("CV") || clean.hasPrefix("CW") { return "🇺🇾" }
    if clean.hasPrefix("CP") { return "🇧🇴" }
    if clean.hasPrefix("TG") || clean.hasPrefix("TD") { return "🇬🇹" }
    if clean.hasPrefix("YS") || clean.hasPrefix("HU") { return "🇸🇻" }
    if clean.hasPrefix("HR") || clean.hasPrefix("HQ") { return "🇭🇳" }
    if clean.hasPrefix("YN") || clean.hasPrefix("HT") { return "🇳🇮" }
    if clean.hasPrefix("TI") || clean.hasPrefix("TE") { return "🇨🇷" }
    if clean.hasPrefix("HP") || clean.hasPrefix("HO") || clean.hasPrefix("3E") || clean.hasPrefix("3F") { return "🇵🇦" }
    if clean.hasPrefix("CO") || clean.hasPrefix("CM") || clean.hasPrefix("CL") || clean.hasPrefix("T4") { return "🇨🇺" }
    if clean.hasPrefix("HH") || clean.hasPrefix("4V") { return "🇭🇹" }
    if clean.hasPrefix("6Y") { return "🇯🇲" }
    if clean.hasPrefix("C6") { return "🇧🇸" }
    if clean.hasPrefix("VP9") { return "🇧🇲" }
    if clean.hasPrefix("V3") { return "🇧🇿" }
    if clean.hasPrefix("8R") { return "🇬🇾" }
    if clean.hasPrefix("PZ") { return "🇸🇷" }
    if clean.hasPrefix("HL") || clean.hasPrefix("DS") || clean.hasPrefix("DT") || clean.hasPrefix("D7") || clean.hasPrefix("D8") || clean.hasPrefix("D9") || clean.hasPrefix("6K") || clean.hasPrefix("6L") || clean.hasPrefix("6M") || clean.hasPrefix("6N") { return "🇰🇷" }
    if clean.hasPrefix("P5") { return "🇰🇵" }
    if clean.hasPrefix("BV") || clean.hasPrefix("BW") || clean.hasPrefix("BX") || clean.hasPrefix("BM") || clean.hasPrefix("BN") || clean.hasPrefix("BO") || clean.hasPrefix("BP") || clean.hasPrefix("BQ") || clean.hasPrefix("BU") { return "🇹🇼" }
    if clean.hasPrefix("VR") { return "🇭🇰" }
    if clean.hasPrefix("XX9") { return "🇲🇴" }
    if clean.hasPrefix("JT") || clean.hasPrefix("JU") || clean.hasPrefix("JV") { return "🇲🇳" }
    if clean.hasPrefix("VU") || clean.hasPrefix("AT") || clean.hasPrefix("AU") || clean.hasPrefix("AV") || clean.hasPrefix("AW") || clean.hasPrefix("8T") || clean.hasPrefix("8U") || clean.hasPrefix("8V") || clean.hasPrefix("8W") || clean.hasPrefix("8X") || clean.hasPrefix("8Y") { return "🇮🇳" }
    if clean.hasPrefix("AP") || clean.hasPrefix("AQ") || clean.hasPrefix("AR") || clean.hasPrefix("AS") || clean.hasPrefix("6S") || clean.hasPrefix("6T") { return "🇵🇰" }
    if clean.hasPrefix("4S") { return "🇱🇰" }
    if clean.hasPrefix("8Q") { return "🇲🇻" }
    if clean.hasPrefix("S2") || clean.hasPrefix("S3") { return "🇧🇩" }
    if clean.hasPrefix("A5") { return "🇧🇹" }
    if clean.hasPrefix("XZ") || clean.hasPrefix("XY") || clean.hasPrefix("1Z") { return "🇲🇲" }
    if clean.hasPrefix("HS") || clean.hasPrefix("E2") { return "🇹🇭" }
    if clean.hasPrefix("XU") { return "🇰🇭" }
    if clean.hasPrefix("XW") { return "🇱🇦" }
    if clean.hasPrefix("3W") || clean.hasPrefix("XV") { return "🇻🇳" }
    if clean.hasPrefix("9M") || clean.hasPrefix("9W") { return "🇲🇾" }
    if clean.hasPrefix("9V") || clean.hasPrefix("S6") { return "🇸🇬" }
    if clean.hasPrefix("V8") { return "🇧🇳" }
    if clean.hasPrefix("YB") || clean.hasPrefix("YC") || clean.hasPrefix("YD") || clean.hasPrefix("YE") || clean.hasPrefix("YF") || clean.hasPrefix("YG") || clean.hasPrefix("YH") || clean.hasPrefix("7A") || clean.hasPrefix("7B") || clean.hasPrefix("7C") || clean.hasPrefix("7D") || clean.hasPrefix("7E") || clean.hasPrefix("7F") || clean.hasPrefix("7G") || clean.hasPrefix("7H") || clean.hasPrefix("7I") || clean.hasPrefix("8A") || clean.hasPrefix("8B") || clean.hasPrefix("8C") || clean.hasPrefix("8D") || clean.hasPrefix("8E") || clean.hasPrefix("8F") || clean.hasPrefix("8G") || clean.hasPrefix("8H") || clean.hasPrefix("8I") { return "🇮🇩" }
    if clean.hasPrefix("4W") { return "🇹🇱" }
    if clean.hasPrefix("DU") || clean.hasPrefix("DV") || clean.hasPrefix("DW") || clean.hasPrefix("DX") || clean.hasPrefix("DY") || clean.hasPrefix("DZ") || clean.hasPrefix("4D") || clean.hasPrefix("4E") || clean.hasPrefix("4F") || clean.hasPrefix("4G") || clean.hasPrefix("4H") || clean.hasPrefix("4I") { return "🇵🇭" }
    if clean.hasPrefix("UN") || clean.hasPrefix("UO") || clean.hasPrefix("UP") || clean.hasPrefix("UQ") { return "🇰🇿" }
    if clean.hasPrefix("UJ") || clean.hasPrefix("UK") || clean.hasPrefix("UL") || clean.hasPrefix("UM") { return "🇺🇿" }
    if clean.hasPrefix("EZ") { return "🇹🇲" }
    if clean.hasPrefix("EX") { return "🇰🇬" }
    if clean.hasPrefix("EY") { return "🇹🇯" }
    if clean.hasPrefix("EK") { return "🇦🇲" }
    if clean.hasPrefix("4J") || clean.hasPrefix("4K") { return "🇦🇿" }
    if clean.hasPrefix("4L") { return "🇬🇪" }
    if clean.hasPrefix("YA") || clean.hasPrefix("T6") { return "🇦🇫" }
    if clean.hasPrefix("HZ") || clean.hasPrefix("7Z") || clean.hasPrefix("8Z") { return "🇸🇦" }
    if clean.hasPrefix("9K") { return "🇰🇼" }
    if clean.hasPrefix("A9") { return "🇧🇭" }
    if clean.hasPrefix("A7") { return "🇶🇦" }
    if clean.hasPrefix("A6") { return "🇦🇪" }
    if clean.hasPrefix("A4") { return "🇴🇲" }
    if clean.hasPrefix("7O") { return "🇾🇪" }
    if clean.hasPrefix("YI") || clean.hasPrefix("HN") { return "🇮🇶" }
    if clean.hasPrefix("JY") { return "🇯🇴" }
    if clean.hasPrefix("4X") || clean.hasPrefix("4Z") { return "🇮🇱" }
    if clean.hasPrefix("E4") { return "🇵🇸" }
    if clean.hasPrefix("OD") { return "🇱🇧" }
    if clean.hasPrefix("YK") || clean.hasPrefix("6C") { return "🇸🇾" }
    if clean.hasPrefix("TA") || clean.hasPrefix("TB") || clean.hasPrefix("TC") || clean.hasPrefix("YM") { return "🇹🇷" }
    if clean.hasPrefix("SU") || clean.hasPrefix("6A") || clean.hasPrefix("6B") { return "🇪🇬" }
    if clean.hasPrefix("5A") { return "🇱🇾" }
    if clean.hasPrefix("3V") || clean.hasPrefix("TS") { return "🇹🇳" }
    if clean.hasPrefix("7X") || clean.hasPrefix("7R") || clean.hasPrefix("7T") || clean.hasPrefix("7U") || clean.hasPrefix("7V") || clean.hasPrefix("7W") || clean.hasPrefix("7Y") { return "🇩🇿" }
    if clean.hasPrefix("CN") || clean.hasPrefix("5C") || clean.hasPrefix("5D") || clean.hasPrefix("5E") || clean.hasPrefix("5F") || clean.hasPrefix("5G") { return "🇲🇦" }
    if clean.hasPrefix("S0") { return "🇪🇭" }
    if clean.hasPrefix("ST") || clean.hasPrefix("6S") || clean.hasPrefix("6U") { return "🇸🇩" }
    if clean.hasPrefix("Z8") { return "🇸🇸" }
    if clean.hasPrefix("E3") { return "🇪🇷" }
    if clean.hasPrefix("ET") || clean.hasPrefix("9E") || clean.hasPrefix("9F") { return "🇪🇹" }
    if clean.hasPrefix("J2") { return "🇩🇯" }
    if clean.hasPrefix("6O") { return "🇸🇴" }
    if clean.hasPrefix("5Z") || clean.hasPrefix("5Y") { return "🇰🇪" }
    if clean.hasPrefix("5X") { return "🇺🇬" }
    if clean.hasPrefix("5H") || clean.hasPrefix("5I") { return "🇹🇿" }
    if clean.hasPrefix("9X") { return "🇷🇼" }
    if clean.hasPrefix("9U") { return "🇧🇮" }
    if clean.hasPrefix("9J") || clean.hasPrefix("9I") { return "🇿🇲" }
    if clean.hasPrefix("7Q") { return "🇲🇼" }
    if clean.hasPrefix("A2") || clean.hasPrefix("8O") { return "🇧🇼" }
    if clean.hasPrefix("V5") { return "🇳🇦" }
    if clean.hasPrefix("ZS") || clean.hasPrefix("ZR") || clean.hasPrefix("ZT") || clean.hasPrefix("ZU") { return "🇿🇦" }
    if clean.hasPrefix("3DA") { return "🇸🇿" }
    if clean.hasPrefix("7P") { return "🇱🇸" }
    if clean.hasPrefix("D2") || clean.hasPrefix("D3") { return "🇦🇴" }
    if clean.hasPrefix("TN") { return "🇨🇬" }
    if clean.hasPrefix("9Q") || clean.hasPrefix("9R") || clean.hasPrefix("9S") || clean.hasPrefix("9T") { return "🇨🇩" }
    if clean.hasPrefix("TR") { return "🇬🇦" }
    if clean.hasPrefix("TJ") { return "🇨🇲" }
    if clean.hasPrefix("3C") { return "🇬🇶" }
    if clean.hasPrefix("S9") { return "🇸🇹" }
    if clean.hasPrefix("TL") { return "🇨🇫" }
    if clean.hasPrefix("TT") { return "🇹🇩" }
    if clean.hasPrefix("5U") { return "🇳🇪" }
    if clean.hasPrefix("TZ") { return "🇲🇱" }
    if clean.hasPrefix("5T") { return "🇲🇷" }
    if clean.hasPrefix("XT") { return "🇧🇫" }
    if clean.hasPrefix("3X") { return "🇬🇳" }
    if clean.hasPrefix("J5") { return "🇬🇼" }
    if clean.hasPrefix("EL") || clean.hasPrefix("5L") || clean.hasPrefix("5M") || clean.hasPrefix("6Z") || clean.hasPrefix("A8") || clean.hasPrefix("D5") { return "🇱🇷" }
    if clean.hasPrefix("9L") { return "🇸🇱" }
    if clean.hasPrefix("TU") { return "🇨🇮" }
    if clean.hasPrefix("9G") { return "🇬🇭" }
    if clean.hasPrefix("5V") { return "🇹🇬" }
    if clean.hasPrefix("TY") { return "🇧🇯" }
    if clean.hasPrefix("D4") { return "🇨🇻" }
    if clean.hasPrefix("5R") || clean.hasPrefix("5S") || clean.hasPrefix("6X") { return "🇲🇬" }
    if clean.hasPrefix("3B") { return "🇲🇺" }
    if clean.hasPrefix("D6") { return "🇰🇲" }
    if clean.hasPrefix("S7") { return "🇸🇨" }
    if clean.hasPrefix("VQ9") { return "🇮🇴" }
    if clean.hasPrefix("H4") { return "🇸🇧" }
    if clean.hasPrefix("YJ") { return "🇻🇺" }
    if clean.hasPrefix("FK") { return "🇳🇨" }
    if clean.hasPrefix("3D2") { return "🇫🇯" }
    if clean.hasPrefix("A3") { return "🇹🇴" }
    if clean.hasPrefix("5W") { return "🇼🇸" }
    if clean.hasPrefix("E6") { return "🇳🇺" }
    if clean.hasPrefix("E5") { return "🇨🇰" }
    if clean.hasPrefix("ZK3") { return "🇹🇰" }
    if clean.hasPrefix("T2") { return "🇹🇻" }
    if clean.hasPrefix("T3") { return "🇰🇮" }
    if clean.hasPrefix("C2") { return "🇳🇷" }
    if clean.hasPrefix("V7") { return "🇲🇭" }
    if clean.hasPrefix("V6") { return "🇫🇲" }
    if clean.hasPrefix("T8") { return "🇵🇼" }
    if clean.hasPrefix("FO") { return "🇵🇫" }

    return nil
}

nonisolated func countryToFlag(_ country: String) -> String {
    let clean = canonicalCountryName(country).lowercased()
    if clean.isEmpty || clean == "n/a" || clean == "none" || clean == "-" { return "🌐" }
    
    switch clean {
    // MARK: - Arctic, Polar & Special DXCC Entities
    case "franz josef land", "franz joseph land", "franz-josef land": return "🇷🇺"
    case "antarctica", "antarctic", "south pole", "queen maud land": return "🇦🇶"
    case "peter 1 is.", "peter 1 island", "peter i island": return "🇦🇶"
    case "bouvet is.", "bouvet island", "bouvet": return "🇧🇻"
    case "heard is.", "heard island", "heard island and mcdonald islands": return "🇭🇲"
    case "macquarie is.", "macquarie island": return "🇦🇺"
    case "prince edward & marion is.", "prince edward and marion is.", "marion is.": return "🇿🇦"
    case "crozet is.", "crozet islands", "crozet": return "🇹🇫"
    case "kerguelen is.", "kerguelen islands", "kerguelen": return "🇹🇫"
    case "amsterdam & st. paul is.", "amsterdam & st paul", "amsterdam and st. paul is.", "st. paul is.": return "🇹🇫"
    case "juan de nova, europa", "juan de nova", "europa is.": return "🇹🇫"
    case "glorioso is.", "glorioso islands", "glorioso": return "🇹🇫"
    case "tromelin is.", "tromelin island", "tromelin": return "🇹🇫"
    case "french southern territories", "french southern & antarctic lands": return "🇹🇫"
    case "san andres and providencia", "san andres & providencia", "san andres island", "san andres is.", "san andres", "san andrés": return "🇨🇴"
    case "malpelo is.", "malpelo island", "malpelo": return "🇨🇴"
    case "galapagos is.", "galapagos islands", "galapagos": return "🇪🇨"
    case "cocos is.", "cocos island", "isla del coco": return "🇨🇷"
    case "easter is.", "easter island", "isla de pascua": return "🇨🇱"
    case "juan fernandez is.", "juan fernandez islands", "juan fernandez": return "🇨🇱"
    case "san felix & san ambrosio", "san felix", "san ambrosio": return "🇨🇱"
    case "revillagigedo is.", "revillagigedo", "socorro is.": return "🇲🇽"
    case "fernando de noronha", "noronha": return "🇧🇷"
    case "st. peter & st. paul rocks", "st. peter and st. paul", "saint peter and saint paul": return "🇧🇷"
    case "trindade & martim vaz", "trindade and martim vaz", "trindade": return "🇧🇷"
    case "aves is.", "aves island", "isla de aves": return "🇻🇪"
    case "falkland is.", "falkland islands", "falkland": return "🇫🇰"
    case "south georgia is.", "south georgia", "south georgia and south sandwich is.": return "🇬🇸"
    case "south sandwich is.", "south sandwich islands": return "🇬🇸"
    case "south orkney is.", "south orkney islands": return "🇦🇶"
    case "south shetland is.", "south shetland islands": return "🇦🇶"
    case "pitcairn is.", "pitcairn island", "pitcairn", "ducie is.", "henderson is.", "oeno is.": return "🇵🇳"
    case "clipperton is.", "clipperton island", "clipperton": return "🇨🇵"
    case "chatham is.", "chatham islands", "chatham": return "🇳🇿"
    case "kermadec is.", "kermadec islands", "kermadec": return "🇳🇿"
    case "auckland & campbell is.", "auckland and campbell is.", "campbell is.": return "🇳🇿"
    case "lord howe is.", "lord howe island": return "🇦🇺"
    case "norfolk is.", "norfolk island": return "🇳🇫"
    case "christmas is.", "christmas island": return "🇨🇽"
    case "cocos (keeling) is.", "cocos (keeling) islands", "cocos keeling islands", "cocos keeling": return "🇨🇨"
    case "mellish reef": return "🇦🇺"
    case "willis is.", "willis island": return "🇦🇺"
    case "chesternfield is.", "chesterfield is.", "chesterfield": return "🇳🇨"
    case "rotuma is.", "rotuma island", "rotuma": return "🇫🇯"
    case "conway reef": return "🇫🇯"
    case "banaba is.", "banaba island", "ocean island": return "🇰🇮"
    case "temotu province", "temotu": return "🇸🇧"
    case "minami torishima", "marcus is.": return "🇯🇵"
    case "ogasawara", "bonin is.", "volcano is.": return "🇯🇵"
    case "pratas is.", "pratas island", "tungsha": return "🇹🇼"
    case "scarborough reef", "huangyan island": return "🇵🇭"
    case "spratly is.", "spratly islands": return "🇻🇳"
    case "paracel is.", "paracel islands": return "🇨🇳"
    case "andaman & nicobar is.", "andaman and nicobar is.", "andaman is.": return "🇮🇳"
    case "lakshadweep is.", "lakshadweep": return "🇮🇳"
    case "chagos is.", "diego garcia", "british indian ocean territory": return "🇮🇴"
    case "socotra is.", "socotra island", "socotra": return "🇾🇪"

    // MARK: - Special DXCC Island Entities, UN & Overseas Territories
    case "rodriguez is.", "rodrigues is.", "rodrigues island", "rodrigues": return "🇲🇺"
    case "agalega & st. brandon", "agalega", "st. brandon": return "🇲🇺"
    case "dodecanese": return "🇬🇷"
    case "montserrat": return "🇲🇸"
    case "western sahara": return "🇪🇭"
    case "central kiribati", "kiribati", "line is.", "phoenix is.", "gilbert is.": return "🇰🇮"
    case "united nations hq", "un hq", "united nations", "itu geneva", "un vienna": return "🇺🇳"
    case "fiji islands", "fiji": return "🇫🇯"
    case "canary is.", "canary islands", "canary island", "canary": return "🇮🇨"
    case "sardinia": return "🇮🇹"
    case "sicily": return "🇮🇹"
    case "crete": return "🇬🇷◈"
    case "azores", "azores is.": return "🇵🇹"
    case "balearic is.", "balearic islands": return "🇪🇸"
    case "bonaire", "saba & st. eustatius", "saba and st. eustatius", "saba", "st. eustatius": return "🇧🇶"
    case "corsica": return "🇫🇷"
    case "madeira is.", "madeira": return "🇵🇹"
    case "ceuta & melilla", "ceuta and melilla", "ceuta", "melilla": return "🇪🇸"
    case "curacao": return "🇨🇼"
    case "aruba": return "🇦🇼"
    case "sint maarten": return "🇸🇽"
    case "st. martin", "saint martin": return "🇲🇫"
    case "st. barthelemy", "saint barthelemy", "saint barthélemy", "st. barts": return "🇧🇱"
    case "svalbard": return "🇸🇯"
    case "jan mayen", "bear is.": return "🇸🇯"
    case "faroe is.", "faroe islands", "faroe": return "🇫🇴"
    case "greenland": return "🇬🇱"
    case "aland is.", "aland islands", "aland", "åland islands", "åland": return "🇦🇽"
    case "market reef": return "🇫🇮"
    case "mount athos": return "🇬🇷"
    case "isle of man": return "🇮🇲"
    case "jersey": return "🇯🇪"
    case "guernsey": return "🇬🇬"
    case "gibraltar": return "🇬🇮"
    case "hawaii": return "🇺🇸"
    case "alaska": return "🇺🇸"
    case "puerto rico": return "🇵🇷"
    case "virgin is.", "us virgin is.", "u.s. virgin islands", "virgin islands": return "🇻🇮"
    case "british virgin is.", "british virgin islands": return "🇻🇬"
    case "guam": return "🇬🇺"
    case "northern mariana is.", "saipan": return "🇲🇵"
    case "american samoa": return "🇦🇸"
    case "wake is.", "wake island": return "🇺🇸"
    case "midway is.", "midway island": return "🇺🇸"
    case "johnston atoll": return "🇺🇸"
    case "palmyra & jarvis is.", "palmyra", "jarvis is.": return "🇺🇸"
    case "kingman reef": return "🇺🇸"
    case "baker & howland is.", "baker is.", "howland is.": return "🇺🇸"
    case "navassa is.", "navassa island": return "🇺🇸"
    case "desecheo is.", "desecheo island": return "🇵🇷"
    case "martinique": return "🇲🇶"
    case "guadeloupe": return "🇬🇵"
    case "reunion", "reunion is.", "réunion": return "🇷🇪"
    case "mayotte": return "🇾🇹"
    case "french guiana": return "🇬🇫"
    case "french polynesia", "tahiti", "marquesas is.", "austral is.": return "🇵🇫"
    case "new caledonia": return "🇳🇨"
    case "wallis & futuna is.", "wallis & futuna", "wallis and futuna": return "🇼🇫"
    case "st. pierre & miquelon", "saint pierre and miquelon", "st. pierre and miquelon": return "🇵🇲"
    case "bermuda": return "🇧🇲"
    case "cayman is.", "cayman islands": return "🇰🇾"
    case "turks & caicos is.", "turks and caicos islands", "turks & caicos": return "🇹🇨"
    case "anguilla": return "🇦🇮"
    case "saint helena", "st. helena": return "🇸🇭"
    case "tristan da cunha": return "🇸🇭"
    case "ascension is.", "ascension island", "ascension": return "🇸🇭"
    case "sovereign military order of malta", "smom": return "🇲🇹"
    case "sovereign base areas on cyprus", "akrotiri & dhekelia": return "🇬🇧"

    // MARK: - Americas & Caribbean
    case "belize": return "🇧🇿"
    case "united states", "united states of america", "usa", "u.s.a.": return "🇺🇸"
    case "canada": return "🇨🇦"
    case "mexico": return "🇲🇽"
    case "brazil": return "🇧🇷"
    case "argentina": return "🇦🇷"
    case "chile": return "🇨🇱"
    case "colombia": return "🇨🇴"
    case "peru": return "🇵🇪"
    case "venezuela": return "🇻🇪"
    case "ecuador": return "🇪🇨"
    case "bolivia": return "🇧🇴"
    case "paraguay": return "🇵🇾"
    case "uruguay": return "🇺🇾"
    case "guyana": return "🇬🇾"
    case "suriname": return "🇸🇷"
    case "cuba": return "🇨🇺"
    case "dominican republic": return "🇩🇴"
    case "jamaica": return "🇯🇲"
    case "haiti": return "🇭🇹"
    case "costa rica": return "🇨🇷"
    case "panama": return "🇵🇦"
    case "guatemala": return "🇬🇹"
    case "honduras": return "🇭🇳"
    case "el salvador": return "🇸🇻"
    case "nicaragua": return "🇳🇮"
    case "bahamas": return "🇧🇸"
    case "trinidad & tobago", "trinidad and tobago": return "🇹🇹"
    case "barbados": return "🇧🇧"
    case "antigua & barbuda", "antigua and barbuda", "antigua": return "🇦🇬"
    case "dominica": return "🇩🇲"
    case "grenada": return "🇬🇩"
    case "st. kitts & nevis", "saint kitts and nevis", "st. kitts and nevis": return "🇰🇳"
    case "st. lucia", "saint lucia": return "🇱🇨"
    case "st. vincent & the grenadines", "saint vincent and the grenadines", "st. vincent": return "🇻🇨"

    // MARK: - Africa
    case "mozambique", "republic of mozambique", "mocambique": return "🇲🇿"
    case "madagascar": return "🇲🇬"
    case "mauritius": return "🇲🇺"
    case "comoros": return "🇰🇲"
    case "seychelles": return "🇸🇨"
    case "chad": return "🇹🇩"
    case "cameroon": return "🇨🇲"
    case "congo", "republic of congo", "republic of the congo": return "🇨🇬"
    case "democratic republic of congo", "democratic republic of the congo", "dr congo", "dr congo / zaire": return "🇨🇩"
    case "malawi": return "🇲🇼"
    case "benin": return "🇧🇯"
    case "south africa": return "🇿🇦"
    case "egypt": return "🇪🇬"
    case "nigeria": return "🇳🇬"
    case "kenya": return "🇰🇪"
    case "morocco": return "🇲🇦"
    case "algeria": return "🇩🇿"
    case "tunisia": return "🇹🇳"
    case "libya": return "🇱🇾"
    case "sudan": return "🇸🇩"
    case "south sudan": return "🇸🇸"
    case "ethiopia": return "🇪🇹"
    case "eritrea": return "🇪🇷"
    case "djibouti": return "🇩🇯"
    case "somalia": return "🇸🇴"
    case "ghana": return "🇬🇭"
    case "togo": return "🇹🇬"
    case "senegal": return "🇸🇳"
    case "gambia": return "🇬🇲"
    case "guinea": return "🇬🇳"
    case "guinea-bissau", "guinea bissau": return "🇬🇼"
    case "sierra leone": return "🇸🇱"
    case "liberia": return "🇱🇷"
    case "cote d'ivoire", "ivory coast", "côte d'ivoire": return "🇨🇮"
    case "burkina faso": return "🇧🇫"
    case "mali": return "🇲🇱"
    case "mauritania": return "🇲🇷"
    case "niger": return "🇳🇪"
    case "central african republic", "central african rep.": return "🇨🇫"
    case "gabon": return "🇬🇦"
    case "equatorial guinea": return "🇬🇶"
    case "annobon": return "🇬🇶"
    case "tanzania": return "🇹🇿"
    case "uganda": return "🇺🇬"
    case "rwanda": return "🇷🇼"
    case "burundi": return "🇧🇮"
    case "zimbabwe": return "🇿🇼"
    case "zambia": return "🇿🇲"
    case "namibia": return "🇳🇦"
    case "botswana": return "🇧🇼"
    case "angola": return "🇦🇴"
    case "lesotho": return "🇱🇸"
    case "cape verde", "cabo verde": return "🇨🇻"
    case "eswatini", "swaziland": return "🇸🇿"
    case "sao tome and principe", "sao tome & principe": return "🇸🇹"

    // MARK: - Europe
    case "republic of kosovo", "kosovo": return "🇽🇰"
    case "armenia", "republic of armenia": return "🇦🇲"
    case "england", "uk", "united kingdom", "great britain": return "🇬🇧"
    case "scotland": return "🏴󠁧󠁢󠁳󠁣󠁴󠁿"
    case "wales": return "🏴󠁧󠁢󠁷󠁬󠁳󠁿"
    case "northern ireland": return "🇬🇧"
    case "european russia", "kaliningrad", "russia": return "🇷🇺"
    case "malyj vysotskij is.": return "🇷🇺"
    case "germany", "fed. rep. of germany", "federal republic of germany": return "🇩🇪"
    case "france": return "🇫🇷"
    case "italy": return "🇮🇹"
    case "spain": return "🇪🇸"
    case "portugal": return "🇵🇹"
    case "greece": return "🇬🇷"
    case "netherlands": return "🇳🇱"
    case "belgium": return "🇧🇪"
    case "switzerland": return "🇨🇭"
    case "austria": return "🇦🇹"
    case "poland": return "🇵🇱"
    case "sweden": return "🇸🇪"
    case "norway": return "🇳🇴"
    case "finland": return "🇫🇮"
    case "denmark": return "🇩🇰"
    case "ukraine": return "🇺🇦"
    case "belarus": return "🇧🇾"
    case "czech republic", "czechia": return "🇨🇿"
    case "slovak republic", "slovakia": return "🇸🇰"
    case "hungary": return "🇭🇺"
    case "romania": return "🇷🇴"
    case "bulgaria": return "🇧🇬"
    case "croatia": return "🇭🇷"
    case "serbia": return "🇷🇸"
    case "slovenia": return "🇸🇮"
    case "bosnia and herzegovina", "bosnia-herzegovina", "bosnia & herzegovina", "bosnia": return "🇧🇦"
    case "north macedonia", "macedonia": return "🇲🇰"
    case "albania": return "🇦🇱"
    case "montenegro": return "🇲🇪"
    case "ireland", "republic of ireland": return "🇮🇪"
    case "iceland": return "🇮🇸"
    case "estonia": return "🇪🇪"
    case "latvia": return "🇱🇻"
    case "lithuania": return "🇱🇹"
    case "moldova", "republic of moldova": return "🇲🇩"
    case "cyprus": return "🇨🇾"
    case "malta": return "🇲🇹"
    case "luxembourg": return "🇱🇺"
    case "monaco": return "🇲🇨"
    case "andorra": return "🇦🇩"
    case "san marino": return "🇸🇲"
    case "vatican", "vatican city": return "🇻🇦"
    case "liechtenstein": return "🇱🇮"

    // MARK: - Asia & Middle East
    case "iran", "islamic republic of iran": return "🇮🇷"
    case "republic of korea", "korea, republic of", "korea (republic of)", "south korea", "korea", "rok": return "🇰🇷"
    case "democratic people's republic of korea", "dprk", "korea, d.p.r. of", "north korea": return "🇰🇵"
    case "japan": return "🇯🇵"
    case "china", "people's republic of china", "prc": return "🇨🇳"
    case "asiatic russia": return "🇷🇺"
    case "taiwan", "republic of china": return "🇹🇼"
    case "hong kong": return "🇭🇰"
    case "macao", "macau": return "🇲🇴"
    case "saudi arabia": return "🇸🇦"
    case "india": return "🇮🇳"
    case "pakistan": return "🇵🇰"
    case "turkey", "turkiye": return "🇹🇷"
    case "israel": return "🇮🇱"
    case "indonesia": return "🇮🇩"
    case "philippines": return "🇵🇭"
    case "thailand": return "🇹🇭"
    case "vietnam", "viet nam": return "🇻🇳"
    case "malaysia", "east malaysia", "west malaysia", "sarawak", "sabah": return "🇲🇾"
    case "singapore": return "🇸🇬"
    case "united arab emirates", "uae": return "🇦🇪"
    case "kuwait": return "🇰🇼"
    case "qatar": return "🇶🇦"
    case "oman": return "🇴🇲"
    case "bahrain": return "🇧🇭"
    case "iraq": return "🇮🇶"
    case "jordan": return "🇯🇴"
    case "lebanon": return "🇱🇧"
    case "syria", "syrian arab republic": return "🇸🇾"
    case "yemen": return "🇾🇪"
    case "mongolia": return "🇲🇳"
    case "kazakhstan": return "🇰🇿"
    case "uzbekistan": return "🇺🇿"
    case "turkmenistan": return "🇹🇲"
    case "kyrgyzstan": return "🇰🇬"
    case "tajikistan": return "🇹🇯"
    case "azerbaijan": return "🇦🇿"
    case "georgia": return "🇬🇪"
    case "sri lanka": return "🇱🇰"
    case "maldives": return "🇲🇻"
    case "bangladesh": return "🇧🇩"
    case "nepal": return "🇳🇵"
    case "bhutan": return "🇧🇹"
    case "myanmar", "burma": return "🇲🇲"
    case "cambodia": return "🇰🇭"
    case "laos", "lao pdr": return "🇱🇦"
    case "brunei", "brunei darussalam": return "🇧🇳"
    case "afghanistan": return "🇦🇫"
    case "palestine": return "🇵🇸"

    // MARK: - Oceania & Pacific
    case "australia": return "🇦🇺"
    case "new zealand": return "🇳🇿"
    case "papua new guinea", "png": return "🇵🇬"
    case "solomon is.", "solomon islands": return "🇸🇧"
    case "vanuatu": return "🇻🇺"
    case "tonga": return "🇹🇴"
    case "samoa": return "🇼🇸"
    case "niue": return "🇳🇺"
    case "cook is.", "cook islands", "north cook is.", "south cook is.": return "🇨🇰"
    case "tokelau": return "🇹🇰"
    case "tuvalu": return "🇹🇻"
    case "nauru": return "🇳🇷"
    case "marshall is.", "marshall islands": return "🇲🇭"
    case "micronesia", "chuuk", "kosrae", "pohnpei", "yap": return "🇫🇲"
    case "palau": return "🇵🇼"
    case "timor-leste", "east timor": return "🇹🇱"

    default: break
    }
    
    // Smart Fallback Keyword Search
    if clean.contains("franz josef") { return "🇷🇺" }
    if clean.contains("antarctic") || clean.contains("south pole") { return "🇦🇶" }
    if clean.contains("san andres") { return "🇨🇴" }
    if clean.contains("mozambique") { return "🇲🇿" }
    if clean.contains("papua") { return "🇵🇬" }
    if clean.contains("rodriguez") || clean.contains("rodrigues") { return "🇲🇺" }
    if clean.contains("dodecanese") { return "🇬🇷" }
    if clean.contains("montserrat") { return "🇲🇸" }
    if clean.contains("sahara") { return "🇪🇭" }
    if clean.contains("kiribati") { return "🇰🇮" }
    if clean.contains("united nations") || clean.contains("4u1un") { return "🇺🇳" }
    if clean.contains("fiji") { return "🇫🇯" }
    if clean.contains("chad") { return "🇹🇩" }
    if clean.contains("cameroon") { return "🇨🇲" }
    if clean.contains("democratic") && clean.contains("congo") { return "🇨🇩" }
    if clean.contains("congo") { return "🇨🇬" }
    if clean.contains("kosovo") { return "🇽🇰" }
    if clean.contains("armenia") { return "🇦🇲" }
    if clean.contains("malawi") { return "🇲🇼" }
    if clean.contains("canary") { return "🇮🇨" }
    if clean.contains("sardinia") { return "🇮🇹" }
    if clean.contains("crete") { return "🇬🇷◈" }
    if clean.contains("azores") { return "🇵🇹" }
    if clean.contains("balearic") { return "🇪🇸" }
    if clean.contains("bonaire") { return "🇧🇶" }
    if clean.contains("belize") { return "🇧🇿" }
    if clean.contains("benin") { return "🇧🇯" }
    if clean.contains("curacao") { return "🇨🇼" }
    if clean.contains("galapagos") { return "🇪🇨" }
    if clean.contains("faroe") { return "🇫🇴" }
    if clean.contains("greenland") { return "🇬🇱" }
    if clean.contains("corsica") { return "🇫🇷" }
    if clean.contains("madeira") { return "🇵🇹" }
    if clean.contains("korea") { return "🇰🇷" }
    if clean.contains("russia") { return "🇷🇺" }
    if clean.contains("germany") { return "🇩🇪" }
    if clean.contains("japan") { return "🇯🇵" }
    if clean.contains("china") { return "🇨🇳" }
    if clean.contains("united states") || clean.contains("u.s.a") { return "🇺🇸" }
    if clean.contains("czech") { return "🇨🇿" }
    if clean.contains("slovak") { return "🇸🇰" }
    if clean.contains("trinidad") { return "🇹🇹" }
    if clean.contains("aland") || clean.contains("åland") { return "🇦🇽" }
    if clean.contains("cayman") { return "🇰🇾" }
    if clean.contains("bermuda") { return "🇧🇲" }
    if clean.contains("falkland") { return "🇫🇰" }
    if clean.contains("svalbard") { return "🇸🇯" }
    if clean.contains("jan mayen") { return "🇸🇯" }
    if clean.contains("marianas") || clean.contains("mariana") { return "🇲🇵" }
    if clean.contains("samoa") { return clean.contains("american") ? "🇦🇸" : "🇼🇸" }
    if clean.contains("guam") { return "🇬🇺" }
    if clean.contains("puerto rico") { return "🇵🇷" }
    if clean.contains("virgin island") || clean.contains("virgin is.") {
        return clean.contains("british") ? "🇻🇬" : "🇻🇮"
    }

    // Dynamic ISO 2-letter Country Code Emoji Builder
    if clean.count == 2 && clean.allSatisfy({ $0.isLetter }) {
        let base: UInt32 = 127397
        var unicodeScalars = String.UnicodeScalarView()
        for scalar in clean.uppercased().unicodeScalars {
            if let newScalar = UnicodeScalar(base + scalar.value) {
                unicodeScalars.append(newScalar)
            }
        }
        return String(unicodeScalars)
    }

    // Callsign prefix fallback
    if let prefixFlag = flagFromCallsignPrefix(country) {
        return prefixFlag
    }
    
    return "🌐"
}
