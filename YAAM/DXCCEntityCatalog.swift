import Foundation

/// ADIF 3.1.8 DXCC enumeration (2026-10-12), including deleted entities.
/// Source: https://adif.org.uk/318/ADIF_318.htm#DXCC_Entity_Code_Enumeration
/// Display aliases also use the bundled CTY file; entity identity is always the ADIF number.
nonisolated enum DXCCEntityCatalog {
    struct Entity: Hashable, Sendable {
        let code: Int
        let name: String
        let isDeleted: Bool
    }
    static let byCode: [Int: Entity] = {
        Dictionary(uniqueKeysWithValues: rows.map { row in
            let code = Int(row[0])!
            return (code, Entity(code: code, name: canonicalCountryName(row[1]) + (row[2] == "Y" ? " (deleted)" : ""), isDeleted: row[2] == "Y"))
        })
    }()
    static let codesByName: [String: Set<Int>] = {
        var result: [String: Set<Int>] = [:]
        for row in rows {
            let code = Int(row[0])!
            for name in [row[1], row[3]] {
                result[CountryNameNormalizer.canonicalKey(name), default: []].insert(code)
            }
        }
        return result
    }()
    static func entity(named name: String) -> Entity? {
        guard let codes = codesByName[CountryNameNormalizer.canonicalKey(name)] else { return nil }
        let current = codes.filter { byCode[$0]?.isDeleted == false }
        let candidates = current.isEmpty ? codes : Set(current)
        guard candidates.count == 1, let code = candidates.first else { return nil }
        return byCode[code]
    }
    private static let rows: [[String]] = data.split(separator: "\n").map {
        $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    }
    private static let data = """
    1|Canada||CANADA
    2|ABU AIL IS.|Y|ABU AIL IS.
    3|Afghanistan||AFGHANISTAN
    4|Agalega & St. Brandon||AGALEGA & ST. BRANDON IS.
    5|Aland Islands||ALAND IS.
    6|Alaska||ALASKA
    7|Albania||ALBANIA
    8|ALDABRA|Y|ALDABRA
    9|American Samoa||AMERICAN SAMOA
    10|Amsterdam & St. Paul Is.||AMSTERDAM & ST. PAUL IS.
    11|Andaman & Nicobar Is.||ANDAMAN & NICOBAR IS.
    12|Anguilla||ANGUILLA
    13|Antarctica||ANTARCTICA
    14|Armenia||ARMENIA
    15|Asiatic Russia||ASIATIC RUSSIA
    16|N.Z. Subantarctic Is.||NEW ZEALAND SUBANTARCTIC ISLANDS
    17|Aves Island||AVES I.
    18|Azerbaijan||AZERBAIJAN
    19|BAJO NUEVO|Y|BAJO NUEVO
    20|Baker & Howland Islands||BAKER & HOWLAND IS.
    21|Balearic Islands||BALEARIC IS.
    22|Palau||PALAU
    23|BLENHEIM REEF|Y|BLENHEIM REEF
    24|Bouvet||BOUVET
    25|BRITISH NORTH BORNEO|Y|BRITISH NORTH BORNEO
    26|BRITISH SOMALILAND|Y|BRITISH SOMALILAND
    27|Belarus||BELARUS
    28|CANAL ZONE|Y|CANAL ZONE
    29|Canary Islands||CANARY IS.
    30|CELEBE & MOLUCCA IS.|Y|CELEBE & MOLUCCA IS.
    31|Central Kiribati||C. KIRIBATI (BRITISH PHOENIX IS.)
    32|Ceuta & Melilla||CEUTA & MELILLA
    33|Chagos Islands||CHAGOS IS.
    34|Chatham Islands||CHATHAM IS.
    35|Christmas Island||CHRISTMAS I.
    36|Clipperton Island||CLIPPERTON I.
    37|Cocos Island||COCOS I.
    38|Cocos (Keeling) Islands||COCOS (KEELING) IS.
    39|COMOROS|Y|COMOROS
    40|Crete||CRETE
    41|Crozet Island||CROZET I.
    42|DAMAO, DIU|Y|DAMAO, DIU
    43|Desecheo Island||DESECHEO I.
    44|DESROCHES|Y|DESROCHES
    45|Dodecanese||DODECANESE
    46|East Malaysia||EAST MALAYSIA
    47|Easter Island||EASTER I.
    48|Eastern Kiribati||E. KIRIBATI (LINE IS.)
    49|Equatorial Guinea||EQUATORIAL GUINEA
    50|Mexico||MEXICO
    51|Eritrea||ERITREA
    52|Estonia||ESTONIA
    53|Ethiopia||ETHIOPIA
    54|European Russia||EUROPEAN RUSSIA
    55|FARQUHAR|Y|FARQUHAR
    56|Fernando de Noronha||FERNANDO DE NORONHA
    57|FRENCH EQUATORIAL AFRICA|Y|FRENCH EQUATORIAL AFRICA
    58|FRENCH INDO-CHINA|Y|FRENCH INDO-CHINA
    59|FRENCH WEST AFRICA|Y|FRENCH WEST AFRICA
    60|Bahamas||BAHAMAS
    61|Franz Josef Land||FRANZ JOSEF LAND
    62|Barbados||BARBADOS
    63|French Guiana||FRENCH GUIANA
    64|Bermuda||BERMUDA
    65|British Virgin Islands||BRITISH VIRGIN IS.
    66|Belize||BELIZE
    67|FRENCH INDIA|Y|FRENCH INDIA
    68|KUWAIT/SAUDI ARABIA NEUTRAL ZONE|Y|KUWAIT/SAUDI ARABIA NEUTRAL ZONE
    69|Cayman Islands||CAYMAN IS.
    70|Cuba||CUBA
    71|Galapagos Islands||GALAPAGOS IS.
    72|Dominican Republic||DOMINICAN REPUBLIC
    74|El Salvador||EL SALVADOR
    75|Georgia||GEORGIA
    76|Guatemala||GUATEMALA
    77|Grenada||GRENADA
    78|Haiti||HAITI
    79|Guadeloupe||GUADELOUPE
    80|Honduras||HONDURAS
    81|GERMANY|Y|GERMANY
    82|Jamaica||JAMAICA
    84|Martinique||MARTINIQUE
    85|BONAIRE, CURACAO|Y|BONAIRE, CURACAO
    86|Nicaragua||NICARAGUA
    88|Panama||PANAMA
    89|Turks & Caicos Islands||TURKS & CAICOS IS.
    90|Trinidad & Tobago||TRINIDAD & TOBAGO
    91|Aruba||ARUBA
    93|GEYSER REEF|Y|GEYSER REEF
    94|Antigua & Barbuda||ANTIGUA & BARBUDA
    95|Dominica||DOMINICA
    96|Montserrat||MONTSERRAT
    97|St. Lucia||ST. LUCIA
    98|St. Vincent||ST. VINCENT
    99|Glorioso Islands||GLORIOSO IS.
    100|Argentina||ARGENTINA
    101|GOA|Y|GOA
    102|GOLD COAST, TOGOLAND|Y|GOLD COAST, TOGOLAND
    103|Guam||GUAM
    104|Bolivia||BOLIVIA
    105|Guantanamo Bay||GUANTANAMO BAY
    106|Guernsey||GUERNSEY
    107|Guinea||GUINEA
    108|Brazil||BRAZIL
    109|Guinea-Bissau||GUINEA-BISSAU
    110|Hawaii||HAWAII
    111|Heard Island||HEARD I.
    112|Chile||CHILE
    113|IFNI|Y|IFNI
    114|Isle of Man||ISLE OF MAN
    115|ITALIAN SOMALILAND|Y|ITALIAN SOMALILAND
    116|Colombia||COLOMBIA
    117|ITU HQ||ITU HQ
    118|Jan Mayen||JAN MAYEN
    119|JAVA|Y|JAVA
    120|Ecuador||ECUADOR
    122|Jersey||JERSEY
    123|Johnston Island||JOHNSTON I.
    124|Juan de Nova, Europa||JUAN DE NOVA, EUROPA
    125|Juan Fernandez Islands||JUAN FERNANDEZ IS.
    126|Kaliningrad||KALININGRAD
    127|KAMARAN IS.|Y|KAMARAN IS.
    128|KARELO-FINNISH REPUBLIC|Y|KARELO-FINNISH REPUBLIC
    129|Guyana||GUYANA
    130|Kazakhstan||KAZAKHSTAN
    131|Kerguelen Islands||KERGUELEN IS.
    132|Paraguay||PARAGUAY
    133|Kermadec Islands||KERMADEC IS.
    134|KINGMAN REEF|Y|KINGMAN REEF
    135|Kyrgyzstan||KYRGYZSTAN
    136|Peru||PERU
    137|Republic of Korea||REPUBLIC OF KOREA
    138|Kure Island||KURE I.
    139|KURIA MURIA I.|Y|KURIA MURIA I.
    140|Suriname||SURINAME
    141|Falkland Islands||FALKLAND IS.
    142|Lakshadweep Islands||LAKSHADWEEP IS.
    143|Laos||LAOS
    144|Uruguay||URUGUAY
    145|Latvia||LATVIA
    146|Lithuania||LITHUANIA
    147|Lord Howe Island||LORD HOWE I.
    148|Venezuela||VENEZUELA
    149|Azores||AZORES
    150|Australia||AUSTRALIA
    151|MALYJ VYSOTSKIJ I.|Y|MALYJ VYSOTSKIJ I.
    152|Macao||MACAO
    153|Macquarie Island||MACQUARIE I.
    154|YEMEN ARAB REPUBLIC|Y|YEMEN ARAB REPUBLIC
    155|MALAYA|Y|MALAYA
    157|Nauru||NAURU
    158|Vanuatu||VANUATU
    159|Maldives||MALDIVES
    160|Tonga||TONGA
    161|Malpelo Island||MALPELO I.
    162|New Caledonia||NEW CALEDONIA
    163|Papua New Guinea||PAPUA NEW GUINEA
    164|MANCHURIA|Y|MANCHURIA
    165|Mauritius||MAURITIUS
    166|Mariana Islands||MARIANA IS.
    167|Market Reef||MARKET REEF
    168|Marshall Islands||MARSHALL IS.
    169|Mayotte||MAYOTTE
    170|New Zealand||NEW ZEALAND
    171|Mellish Reef||MELLISH REEF
    172|Pitcairn Island||PITCAIRN I.
    173|Micronesia||MICRONESIA
    174|Midway Island||MIDWAY I.
    175|French Polynesia||FRENCH POLYNESIA
    176|Fiji||FIJI
    177|Minami Torishima||MINAMI TORISHIMA
    178|MINERVA REEF|Y|MINERVA REEF
    179|Moldova||MOLDOVA
    180|Mount Athos||MOUNT ATHOS
    181|Mozambique||MOZAMBIQUE
    182|Navassa Island||NAVASSA I.
    183|NETHERLANDS BORNEO|Y|NETHERLANDS BORNEO
    184|NETHERLANDS NEW GUINEA|Y|NETHERLANDS NEW GUINEA
    185|Solomon Islands||SOLOMON IS.
    186|NEWFOUNDLAND, LABRADOR|Y|NEWFOUNDLAND, LABRADOR
    187|Niger||NIGER
    188|Niue||NIUE
    189|Norfolk Island||NORFOLK I.
    190|Samoa||SAMOA
    191|North Cook Islands||NORTH COOK IS.
    192|Ogasawara||OGASAWARA
    193|OKINAWA (RYUKYU IS.)|Y|OKINAWA (RYUKYU IS.)
    194|OKINO TORI-SHIMA|Y|OKINO TORI-SHIMA
    195|Annobon Island||ANNOBON I.
    196|PALESTINE|Y|PALESTINE
    197|Palmyra & Jarvis Islands||PALMYRA & JARVIS IS.
    198|PAPUA TERRITORY|Y|PAPUA TERRITORY
    199|Peter 1 Island||PETER 1 I.
    200|PORTUGUESE TIMOR|Y|PORTUGUESE TIMOR
    201|Pr. Edward & Marion Is.||PRINCE EDWARD & MARION IS.
    202|Puerto Rico||PUERTO RICO
    203|Andorra||ANDORRA
    204|Revillagigedo||REVILLAGIGEDO
    205|Ascension Island||ASCENSION I.
    206|Austria||AUSTRIA
    207|Rodriguez Island||RODRIGUES I.
    208|RUANDA-URUNDI|Y|RUANDA-URUNDI
    209|Belgium||BELGIUM
    210|SAAR|Y|SAAR
    211|Sable Island||SABLE I.
    212|Bulgaria||BULGARIA
    213|St. Martin||SAINT MARTIN
    214|Corsica||CORSICA
    215|Cyprus||CYPRUS
    216|San Andres & Providencia||SAN ANDRES & PROVIDENCIA
    217|San Felix & San Ambrosio||SAN FELIX & SAN AMBROSIO
    218|CZECHOSLOVAKIA|Y|CZECHOSLOVAKIA
    219|Sao Tome & Principe||SAO TOME & PRINCIPE
    220|SARAWAK|Y|SARAWAK
    221|Denmark||DENMARK
    222|Faroe Islands||FAROE IS.
    223|England||ENGLAND
    224|Finland||FINLAND
    225|Sardinia||SARDINIA
    226|SAUDI ARABIA/IRAQ NEUTRAL ZONE|Y|SAUDI ARABIA/IRAQ NEUTRAL ZONE
    227|France||FRANCE
    228|SERRANA BANK & RONCADOR CAY|Y|SERRANA BANK & RONCADOR CAY
    229|GERMAN DEMOCRATIC REPUBLIC|Y|GERMAN DEMOCRATIC REPUBLIC
    230|Fed. Rep. of Germany||FEDERAL REPUBLIC OF GERMANY
    231|SIKKIM|Y|SIKKIM
    232|Somalia||SOMALIA
    233|Gibraltar||GIBRALTAR
    234|South Cook Islands||SOUTH COOK IS.
    235|South Georgia Island||SOUTH GEORGIA I.
    236|Greece||GREECE
    237|Greenland||GREENLAND
    238|South Orkney Islands||SOUTH ORKNEY IS.
    239|Hungary||HUNGARY
    240|South Sandwich Islands||SOUTH SANDWICH IS.
    241|South Shetland Islands||SOUTH SHETLAND IS.
    242|Iceland||ICELAND
    243|PEOPLE'S DEMOCRATIC REP. OF YEMEN|Y|PEOPLE'S DEMOCRATIC REP. OF YEMEN
    244|SOUTHERN SUDAN|Y|SOUTHERN SUDAN
    245|Ireland||IRELAND
    246|Sov Mil Order of Malta||SOVEREIGN MILITARY ORDER OF MALTA
    247|Spratly Islands||SPRATLY IS.
    248|Italy||ITALY
    249|St. Kitts & Nevis||ST. KITTS & NEVIS
    250|St. Helena||ST. HELENA
    251|Liechtenstein||LIECHTENSTEIN
    252|St. Paul Island||ST. PAUL I.
    253|St. Peter & St. Paul||ST. PETER & ST. PAUL ROCKS
    254|Luxembourg||LUXEMBOURG
    255|ST. MAARTEN, SABA, ST. EUSTATIUS|Y|ST. MAARTEN, SABA, ST. EUSTATIUS
    256|Madeira Islands||MADEIRA IS.
    257|Malta||MALTA
    258|SUMATRA|Y|SUMATRA
    259|Svalbard||SVALBARD
    260|Monaco||MONACO
    261|SWAN IS.|Y|SWAN IS.
    262|Tajikistan||TAJIKISTAN
    263|Netherlands||NETHERLANDS
    264|TANGIER|Y|TANGIER
    265|Northern Ireland||NORTHERN IRELAND
    266|Norway||NORWAY
    267|TERRITORY OF NEW GUINEA|Y|TERRITORY OF NEW GUINEA
    268|TIBET|Y|TIBET
    269|Poland||POLAND
    270|Tokelau Islands||TOKELAU IS.
    271|TRIESTE|Y|TRIESTE
    272|Portugal||PORTUGAL
    273|Trindade & Martim Vaz||TRINDADE & MARTIM VAZ IS.
    274|Tristan da Cunha & Gough||TRISTAN DA CUNHA & GOUGH I.
    275|Romania||ROMANIA
    276|Tromelin Island||TROMELIN I.
    277|St. Pierre & Miquelon||ST. PIERRE & MIQUELON
    278|San Marino||SAN MARINO
    279|Scotland||SCOTLAND
    280|Turkmenistan||TURKMENISTAN
    281|Spain||SPAIN
    282|Tuvalu||TUVALU
    283|UK Base Areas on Cyprus||UK SOVEREIGN BASE AREAS ON CYPRUS
    284|Sweden||SWEDEN
    285|US Virgin Islands||VIRGIN IS.
    286|Uganda||UGANDA
    287|Switzerland||SWITZERLAND
    288|Ukraine||UKRAINE
    289|United Nations HQ||UNITED NATIONS HQ
    291|United States||UNITED STATES OF AMERICA
    292|Uzbekistan||UZBEKISTAN
    293|Vietnam||VIET NAM
    294|Wales||WALES
    295|Vatican City||VATICAN
    296|Serbia||SERBIA
    297|Wake Island||WAKE I.
    298|Wallis & Futuna Islands||WALLIS & FUTUNA IS.
    299|West Malaysia||WEST MALAYSIA
    301|Western Kiribati||W. KIRIBATI (GILBERT IS. )
    302|Western Sahara||WESTERN SAHARA
    303|Willis Island||WILLIS I.
    304|Bahrain||BAHRAIN
    305|Bangladesh||BANGLADESH
    306|Bhutan||BHUTAN
    307|ZANZIBAR|Y|ZANZIBAR
    308|Costa Rica||COSTA RICA
    309|Myanmar||MYANMAR
    312|Cambodia||CAMBODIA
    315|Sri Lanka||SRI LANKA
    318|China||CHINA
    321|Hong Kong||HONG KONG
    324|India||INDIA
    327|Indonesia||INDONESIA
    330|Iran||IRAN
    333|Iraq||IRAQ
    336|Israel||ISRAEL
    339|Japan||JAPAN
    342|Jordan||JORDAN
    344|DPR of Korea||DEMOCRATIC PEOPLE'S REP. OF KOREA
    345|Brunei Darussalam||BRUNEI DARUSSALAM
    348|Kuwait||KUWAIT
    354|Lebanon||LEBANON
    363|Mongolia||MONGOLIA
    369|Nepal||NEPAL
    370|Oman||OMAN
    372|Pakistan||PAKISTAN
    375|Philippines||PHILIPPINES
    376|Qatar||QATAR
    378|Saudi Arabia||SAUDI ARABIA
    379|Seychelles||SEYCHELLES
    381|Singapore||SINGAPORE
    382|Djibouti||DJIBOUTI
    384|Syria||SYRIA
    386|Taiwan||TAIWAN
    387|Thailand||THAILAND
    390|Turkey||TURKEY
    391|United Arab Emirates||UNITED ARAB EMIRATES
    400|Algeria||ALGERIA
    401|Angola||ANGOLA
    402|Botswana||BOTSWANA
    404|Burundi||BURUNDI
    406|Cameroon||CAMEROON
    408|Central African Republic||CENTRAL AFRICA
    409|Cabo Verde||CAPE VERDE
    410|Chad||CHAD
    411|Comoros||COMOROS
    412|Republic of the Congo||REPUBLIC OF THE CONGO
    414|Dem. Rep. of the Congo||DEMOCRATIC REPUBLIC OF THE CONGO
    416|Benin||BENIN
    420|Gabon||GABON
    422|The Gambia||THE GAMBIA
    424|Ghana||GHANA
    428|Cote d'Ivoire||COTE D'IVOIRE
    430|Kenya||KENYA
    432|Lesotho||LESOTHO
    434|Liberia||LIBERIA
    436|Libya||LIBYA
    438|Madagascar||MADAGASCAR
    440|Malawi||MALAWI
    442|Mali||MALI
    444|Mauritania||MAURITANIA
    446|Morocco||MOROCCO
    450|Nigeria||NIGERIA
    452|Zimbabwe||ZIMBABWE
    453|Reunion Island||REUNION I.
    454|Rwanda||RWANDA
    456|Senegal||SENEGAL
    458|Sierra Leone||SIERRA LEONE
    460|Rotuma Island||ROTUMA I.
    462|South Africa||REPUBLIC OF SOUTH AFRICA
    464|Namibia||NAMIBIA
    466|Sudan||SUDAN
    468|Kingdom of Eswatini||KINGDOM OF ESWATINI
    470|Tanzania||TANZANIA
    474|Tunisia||TUNISIA
    478|Egypt||EGYPT
    480|Burkina Faso||BURKINA FASO
    482|Zambia||ZAMBIA
    483|Togo||TOGO
    488|WALVIS BAY|Y|WALVIS BAY
    489|Conway Reef||CONWAY REEF
    490|Banaba Island||BANABA I. (OCEAN I.)
    492|Yemen||YEMEN
    493|PENGUIN IS.|Y|PENGUIN IS.
    497|Croatia||CROATIA
    499|Slovenia||SLOVENIA
    501|Bosnia-Herzegovina||BOSNIA-HERZEGOVINA
    502|North Macedonia||NORTH MACEDONIA (REPUBLIC OF)
    503|Czech Republic||CZECH REPUBLIC
    504|Slovak Republic||SLOVAK REPUBLIC
    505|Pratas Island||PRATAS I.
    506|Scarborough Reef||SCARBOROUGH REEF
    507|Temotu Province||TEMOTU PROVINCE
    508|Austral Islands||AUSTRAL I.
    509|Marquesas Islands||MARQUESAS IS.
    510|Palestine||PALESTINE
    511|Timor - Leste||TIMOR-LESTE
    512|Chesterfield Islands||CHESTERFIELD IS.
    513|Ducie Island||DUCIE I.
    514|Montenegro||MONTENEGRO
    515|Swains Island||SWAINS I.
    516|St. Barthelemy||SAINT BARTHELEMY
    517|Curacao||CURACAO
    518|Sint Maarten||SINT MAARTEN
    519|Saba & St. Eustatius||SABA & ST. EUSTATIUS
    520|Bonaire||BONAIRE
    521|Republic of South Sudan||SOUTH SUDAN (REPUBLIC OF)
    522|Republic of Kosovo||REPUBLIC OF KOSOVO
    """
}
