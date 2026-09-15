import sys, re

print('Reading /opt/qrz-project/app.py for Feature 4 patch...')
with open('/opt/qrz-project/app.py', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Insert CONTINENT_DIVISIONS and helper functions before calculate_achievements
continent_definitions = '''CONTINENT_DIVISIONS = {
    'me': {
        'id': 'me',
        'name': 'Middle East',
        'name_fa': 'خاورمیانه',
        'icon': '🕌',
        'countries': ['ir', 'sa', 'ae', 'kw', 'qa', 'om', 'bh', 'iq', 'jo', 'lb', 'sy', 'ye', 'tr', 'cy', 'eg', 'ps', 'il'],
        'description': 'Middle Eastern & Gulf amateur radio operators'
    },
    'eu': {
        'id': 'eu',
        'name': 'Europe',
        'name_fa': 'اروپا',
        'icon': '🇪🇺',
        'countries': ['de', 'gb', 'it', 'fr', 'es', 'pl', 'nl', 'be', 'ru', 'ua', 'se', 'no', 'fi', 'dk', 'at', 'ch', 'pt', 'gr', 'cz', 'ro', 'hu', 'hr', 'rs', 'bg', 'sk', 'si', 'lt', 'lv', 'ee', 'ie', 'is', 'lu', 'al', 'ba', 'mk', 'md', 'me', 'mt', 'je', 'gg', 'im'],
        'description': 'European Continent (IARU Region 1)'
    },
    'as': {
        'id': 'as',
        'name': 'Asia',
        'name_fa': 'آسیا',
        'icon': '🌏',
        'countries': ['ir', 'jp', 'kr', 'cn', 'in', 'id', 'th', 'my', 'ph', 'sg', 'vn', 'kz', 'tw', 'hk', 'mn', 'kp', 'mv', 'sa', 'ae', 'kw', 'qa', 'om', 'bh', 'iq', 'jo', 'lb', 'sy', 'il', 'ye', 'am', 'az', 'ge'],
        'description': 'Asian Continent (IARU Region 3)'
    },
    'af': {
        'id': 'af',
        'name': 'Africa',
        'name_fa': 'آفریقا',
        'icon': '🌍',
        'countries': ['ma', 'za', 'dz', 'eg', 'ng', 'gh', 'mu', 'sc', 'st', 'gq', 'bw', 'mw', 'zw', 'bf', 'cf'],
        'description': 'African Continent'
    },
    'na': {
        'id': 'na',
        'name': 'North America',
        'name_fa': 'آمریکای شمالی',
        'icon': '🌎',
        'countries': ['us', 'ca', 'mx', 'cu', 'cr', 'pa', 'do', 'pr', 'gt', 'bz', 'sv', 'bb', 'bm', 'ky', 'tt', 'gl', 'aw', 'bq1'],
        'description': 'North American Continent & Caribbean'
    },
    'sa': {
        'id': 'sa',
        'name': 'South America',
        'name_fa': 'آمریکای جنوبی',
        'icon': '🌎',
        'countries': ['br', 'ar', 'cl', 'co', 'pe', 've', 'uy', 'py', 'ec', 'bo'],
        'description': 'South American Continent'
    },
    'oc': {
        'id': 'oc',
        'name': 'Oceania',
        'name_fa': 'اقیانوسیه',
        'icon': '🌏',
        'countries': ['au', 'cc', 'cx', 'fj', 'ki', 'nc', 'nz', 'pn', 'to', 'tv'],
        'description': 'Pacific & Australasia'
    }
}

COUNTRY_TO_CONTINENT = {}
for _div_id, _info in CONTINENT_DIVISIONS.items():
    for _c_iso in _info['countries']:
        if _c_iso not in COUNTRY_TO_CONTINENT:
            COUNTRY_TO_CONTINENT[_c_iso] = []
        COUNTRY_TO_CONTINENT[_c_iso].append(_div_id)

def get_division_operator_total(cursor, isos):
    if not isos:
        return 0
    fmt = ','.join(['%s'] * len(isos))
    cursor.execute(f"SELECT SUM(operator_count) as total FROM qrz_country_summary WHERE country_iso IN ({fmt})", tuple(isos))
    row = cursor.fetchone()
    return int(row['total'] or 0) if row else 0

def get_division_leaderboard(cursor, division_id, category='qso', limit=10):
    div_info = CONTINENT_DIVISIONS.get(division_id)
    if not div_info:
        return None

    cat_col = 'val_score_qso'
    if category == 'countries':
        cat_col = 'val_score_countries'
    elif category == 'band':
        cat_col = 'val_score_band'

    isos = div_info['countries']
    fmt = ','.join(['%s'] * len(isos))
    cursor.execute(f"""
        SELECT callsign, bid, score_qso, val_score_qso, score_countries, val_score_countries,
               score_band, val_score_band, rank_qso, val_rank_qso, country_iso, country_name
        FROM qrz_ranks
        WHERE country_iso IN ({fmt})
        ORDER BY {cat_col} DESC, val_score_qso DESC, callsign ASC
        LIMIT %s
    """, (*isos, limit))
    rows = cursor.fetchall() or []

    leaderboard = []
    for idx, r in enumerate(rows, start=1):
        score_val = r.get(cat_col, 0)
        c_iso = r.get('country_iso') or 'un'
        leaderboard.append({
            'rank_in_division': idx,
            'callsign': r['callsign'],
            'bid': r.get('bid') or '',
            'country_iso': c_iso,
            'country_name': r.get('country_name') or 'Unknown',
            'flag_url': f"https://flagcdn.com/w40/{c_iso}.png" if c_iso != 'un' else '',
            'score': score_val,
            'score_display': f"{score_val:,}",
            'score_qso': f"{r.get('val_score_qso', 0):,}",
            'score_countries': f"{r.get('val_score_countries', 0):,}",
            'score_band': f"{r.get('val_score_band', 0):,}",
            'world_rank': r.get('rank_qso') or '-',
            'val_rank_world': r.get('val_rank_qso') or 999999,
        })

    tot_ops = get_division_operator_total(cursor, isos)
    return {
        'status': 'success',
        'division': {
            'id': div_info['id'],
            'name': div_info['name'],
            'name_fa': div_info['name_fa'],
            'icon': div_info['icon'],
            'description': div_info['description'],
            'country_count': len(isos),
            'total_operators': tot_ops
        },
        'category': category,
        'limit': limit,
        'leaderboard': leaderboard
    }

'''

if 'CONTINENT_DIVISIONS =' not in content:
    ach_anchor = 'def calculate_achievements('
    content = content.replace(ach_anchor, continent_definitions + ach_anchor, 1)
    print('[OK] Added CONTINENT_DIVISIONS and helper functions.')

# 2. Update calculate_station_analysis to include continental_standing
analysis_ret_target = '''        "achievements": calculate_achievements(val_score_qso, val_score_countries, val_score_band, val_rank_qso, nat_rank_qso, country_name)[0],
        "achievements_summary": calculate_achievements(val_score_qso, val_score_countries, val_score_band, val_rank_qso, nat_rank_qso, country_name)[1],
    }'''

analysis_ret_new = '''        "achievements": calculate_achievements(val_score_qso, val_score_countries, val_score_band, val_rank_qso, nat_rank_qso, country_name)[0],
        "achievements_summary": calculate_achievements(val_score_qso, val_score_countries, val_score_band, val_rank_qso, nat_rank_qso, country_name)[1],
        "continental_standing": get_station_continental_standing(cursor, callsign, country_iso, val_score_qso),
    }'''

station_standing_helper = '''def get_station_continental_standing(cursor, callsign, country_iso, val_score_qso):
    if not country_iso:
        return {}
    div_ids = COUNTRY_TO_CONTINENT.get(country_iso.lower(), [])
    standing = {}
    for did in div_ids:
        dinfo = CONTINENT_DIVISIONS[did]
        disos = dinfo['countries']
        dfmt = ','.join(['%s'] * len(disos))
        cursor.execute(f"""
            SELECT COUNT(*) + 1 AS rk
            FROM qrz_ranks
            WHERE country_iso IN ({dfmt}) AND (val_score_qso > %s OR (val_score_qso = %s AND callsign < %s))
        """, (*disos, val_score_qso, val_score_qso, callsign))
        rk_row = cursor.fetchone()
        rk_val = rk_row['rk'] if rk_row else 1
        d_tot = get_division_operator_total(cursor, disos)

        key_prefix = 'region' if did == 'me' else 'continent'
        standing[f"{key_prefix}_id"] = did
        standing[f"{key_prefix}_name"] = dinfo['name']
        standing[f"{key_prefix}_icon"] = dinfo['icon']
        standing[f"{key_prefix}_rank_qso"] = rk_val
        standing[f"{key_prefix}_total_operators"] = d_tot
    return standing

'''

if 'def get_station_continental_standing(' not in content:
    target_calc = 'def calculate_station_analysis(cursor, callsign, db_result):'
    content = content.replace(target_calc, station_standing_helper + target_calc, 1)
    print('[OK] Added get_station_continental_standing helper.')

if '"continental_standing":' not in content and analysis_ret_target in content:
    content = content.replace(analysis_ret_target, analysis_ret_new, 1)
    print('[OK] Integrated continental_standing into calculate_station_analysis.')

# 3. Add tabBtnContinents to mainNavBar in SPA_HTML
nav_target = '''            <button id="tabBtnVersus" class="nav-tab px-4 py-2 rounded-xl text-xs font-bold uppercase tracking-wider flex items-center gap-2">
                <span>⚔️</span> Station Versus
            </button>'''

nav_replacement = '''            <button id="tabBtnVersus" class="nav-tab px-4 py-2 rounded-xl text-xs font-bold uppercase tracking-wider flex items-center gap-2">
                <span>⚔️</span> Station Versus
            </button>
            <button id="tabBtnContinents" class="nav-tab px-4 py-2 rounded-xl text-xs font-bold uppercase tracking-wider flex items-center gap-2">
                <span>🌍</span> Continents &amp; Regions
            </button>'''

if 'id="tabBtnContinents"' not in content and nav_target in content:
    content = content.replace(nav_target, nav_replacement, 1)
    print('[OK] Added tabBtnContinents to mainNavBar.')

# 4. Add viewContinents right after viewVersus
view_versus_end = '''                        <div class="flex items-center justify-between text-[10px] text-slate-400">
                            <span id="vsBandRank1">Rank: -</span>
                            <span id="vsBandDelta" class="font-bold text-white px-2 py-0.5 rounded bg-slate-800">--</span>
                            <span id="vsBandRank2">Rank: -</span>
                        </div>
                    </div>
                </div>
            </div>
        </div>'''

view_continents_code = '''                        <div class="flex items-center justify-between text-[10px] text-slate-400">
                            <span id="vsBandRank1">Rank: -</span>
                            <span id="vsBandDelta" class="font-bold text-white px-2 py-0.5 rounded bg-slate-800">--</span>
                            <span id="vsBandRank2">Rank: -</span>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Continental & Regional Divisions Leaderboards -->
        <div id="viewContinents" class="hidden space-y-6">
            <!-- Header Hero Card -->
            <div class="bg-gradient-to-r from-slate-900/90 via-emerald-950/30 to-slate-900/90 border border-emerald-500/30 p-6 rounded-2xl">
                <div class="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-emerald-400">
                    <span>🌍</span> Regional &amp; Continental Divisions
                </div>
                <h2 class="text-2xl font-black text-white mt-1">Continental Leaderboards &amp; Benchmark Divisions</h2>
                <p class="text-xs text-slate-400 mt-1">Explore elite operator standings across Europe, Asia, Middle East, Africa, the Americas, and Oceania.</p>

                <!-- Division Selector Pills -->
                <div class="mt-5 space-y-2">
                    <span class="text-[10px] font-bold uppercase tracking-wider text-slate-400 block">Select Continental Division</span>
                    <div class="flex flex-wrap gap-2" id="continentDivisionPills">
                        <button class="cont-div-btn active px-3.5 py-1.5 rounded-xl text-xs font-bold bg-emerald-600 border border-emerald-500 text-white flex items-center gap-1.5 shadow-lg shadow-emerald-600/20 transition-all" data-div="me">
                            <span>🕌</span> Middle East (خاورمیانه)
                        </button>
                        <button class="cont-div-btn px-3.5 py-1.5 rounded-xl text-xs font-bold bg-slate-900/80 border border-slate-700/60 text-slate-300 hover:text-white flex items-center gap-1.5 transition-all" data-div="eu">
                            <span>🇪🇺</span> Europe (اروپا)
                        </button>
                        <button class="cont-div-btn px-3.5 py-1.5 rounded-xl text-xs font-bold bg-slate-900/80 border border-slate-700/60 text-slate-300 hover:text-white flex items-center gap-1.5 transition-all" data-div="as">
                            <span>🌏</span> Asia (آسیا)
                        </button>
                        <button class="cont-div-btn px-3.5 py-1.5 rounded-xl text-xs font-bold bg-slate-900/80 border border-slate-700/60 text-slate-300 hover:text-white flex items-center gap-1.5 transition-all" data-div="af">
                            <span>🌍</span> Africa (آفریقا)
                        </button>
                        <button class="cont-div-btn px-3.5 py-1.5 rounded-xl text-xs font-bold bg-slate-900/80 border border-slate-700/60 text-slate-300 hover:text-white flex items-center gap-1.5 transition-all" data-div="na">
                            <span>🌎</span> North America (آمریکای شمالی)
                        </button>
                        <button class="cont-div-btn px-3.5 py-1.5 rounded-xl text-xs font-bold bg-slate-900/80 border border-slate-700/60 text-slate-300 hover:text-white flex items-center gap-1.5 transition-all" data-div="sa">
                            <span>🌎</span> South America (آمریکای جنوبی)
                        </button>
                        <button class="cont-div-btn px-3.5 py-1.5 rounded-xl text-xs font-bold bg-slate-900/80 border border-slate-700/60 text-slate-300 hover:text-white flex items-center gap-1.5 transition-all" data-div="oc">
                            <span>🌏</span> Oceania (اقیانوسیه)
                        </button>
                    </div>
                </div>

                <!-- Controls: Categories and Limits -->
                <div class="mt-5 pt-4 border-t border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-3 flex-wrap">
                    <!-- Categories -->
                    <div class="flex items-center gap-1.5 bg-slate-950/60 p-1 rounded-xl border border-slate-800">
                        <button class="cont-cat-btn px-3 py-1 rounded-lg text-xs font-bold bg-emerald-600 text-white transition-all" data-cat="qso">QSOs</button>
                        <button class="cont-cat-btn px-3 py-1 rounded-lg text-xs font-bold text-slate-400 hover:text-white transition-all" data-cat="countries">DXCC Countries</button>
                        <button class="cont-cat-btn px-3 py-1 rounded-lg text-xs font-bold text-slate-400 hover:text-white transition-all" data-cat="band">Band-Slots</button>
                    </div>

                    <!-- Limits & Meta -->
                    <div class="flex items-center gap-3">
                        <span id="contMetaInfo" class="text-xs font-bold text-slate-400">Loading division telemetry...</span>
                        <div class="flex items-center gap-1 bg-slate-950/60 p-1 rounded-xl border border-slate-800">
                            <button class="cont-limit-btn px-2.5 py-1 rounded-lg text-xs font-bold bg-slate-800 text-emerald-300" data-limit="10">Top 10</button>
                            <button class="cont-limit-btn px-2.5 py-1 rounded-lg text-xs font-bold text-slate-400 hover:text-white" data-limit="25">Top 25</button>
                            <button class="cont-limit-btn px-2.5 py-1 rounded-lg text-xs font-bold text-slate-400 hover:text-white" data-limit="50">Top 50</button>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Continental Podium: Top 3 Stations -->
            <div id="continentsPodium" class="grid grid-cols-1 sm:grid-cols-3 gap-4"></div>

            <!-- Full Continental Leaderboard Table -->
            <div class="bg-slate-900/60 border border-slate-800 rounded-2xl overflow-hidden shadow-xl">
                <div class="p-4 border-b border-slate-800 flex items-center justify-between">
                    <h3 id="contTableTitle" class="text-sm font-bold text-white uppercase tracking-wider flex items-center gap-2">
                        <span>🏆</span> Continental Standing Table
                    </h3>
                    <span id="contTableCount" class="text-xs text-slate-400 font-mono">-- stations</span>
                </div>
                <div class="overflow-x-auto">
                    <table class="w-full text-left border-collapse text-xs">
                        <thead>
                            <tr class="border-b border-slate-800 bg-slate-950/50 text-[10px] font-bold text-slate-400 uppercase tracking-wider">
                                <th class="py-3 px-4 w-16 text-center">Rank</th>
                                <th class="py-3 px-4">Callsign</th>
                                <th class="py-3 px-4">Country</th>
                                <th class="py-3 px-4" id="contTableHeaderScore">Score (QSOs)</th>
                                <th class="py-3 px-4">DXCC / Bands</th>
                                <th class="py-3 px-4">World Rank</th>
                                <th class="py-3 px-4 text-right">Actions</th>
                            </tr>
                        </thead>
                        <tbody id="continentsTableBody" class="divide-y divide-slate-800/60 text-slate-200 font-mono"></tbody>
                    </table>
                </div>
            </div>
        </div>'''

if 'id="viewContinents"' not in content and view_versus_end in content:
    content = content.replace(view_versus_end, view_continents_code, 1)
    print('[OK] Added viewContinents HTML to template.')

# 5. Update switchTab in JS
js_switch_old = "const tabs = ['lookup', 'versus', 'national', 'global', 'simulator'];"
js_switch_new = "const tabs = ['lookup', 'versus', 'continents', 'national', 'global', 'simulator'];"

if js_switch_old in content:
    content = content.replace(js_switch_old, js_switch_new, 1)
    print('[OK] Added continents to switchTab array.')

# In switchTab, add loading logic:
js_switch_action_old = '''            } else if (tab === 'global') {
                loadGlobalLeaderboard();'''

js_switch_action_new = '''            } else if (tab === 'continents') {
                loadDivisionLeaderboard();
            } else if (tab === 'global') {
                loadGlobalLeaderboard();'''

if js_switch_action_old in content:
    content = content.replace(js_switch_action_old, js_switch_action_new, 1)
    print('[OK] Added loadDivisionLeaderboard trigger to switchTab.')

# 6. Add Division Leaderboard JavaScript controller
js_div_controller = '''        // --- STANDOUT FEATURE 4: CONTINENTAL & REGIONAL DIVISIONS CONTROLLER ---
        let currentDivisionId = 'me';
        let currentDivisionCategory = 'qso';
        let currentDivisionLimit = 10;
        let cachedDivisions = {};

        async function loadDivisionLeaderboard() {
            const divId = currentDivisionId || 'me';
            const cat = currentDivisionCategory || 'qso';
            const limit = currentDivisionLimit || 10;

            const podiumEl = document.getElementById('continentsPodium');
            const tbody = document.getElementById('continentsTableBody');
            const metaEl = document.getElementById('contMetaInfo');
            const titleEl = document.getElementById('contTableTitle');
            const countEl = document.getElementById('contTableCount');
            const scoreHeader = document.getElementById('contTableHeaderScore');

            if (scoreHeader) {
                scoreHeader.textContent = cat === 'qso' ? 'Score (QSOs)' : (cat === 'countries' ? 'DXCC Countries' : 'Band-Country Slots');
            }

            if (podiumEl) podiumEl.innerHTML = '<div class="col-span-3 text-center py-8 text-slate-400 text-xs">Loading continental telemetry...</div>';
            if (tbody) tbody.innerHTML = '<tr><td colspan="7" class="py-8 text-center text-slate-400 text-xs">Syncing division leaderboard...</td></tr>';

            const cacheKey = `${divId}:${cat}:${limit}`;
            if (cachedDivisions[cacheKey]) {
                renderDivisionData(cachedDivisions[cacheKey]);
                return;
            }

            try {
                const res = await fetch(`/api/v1/leaderboard/division/${encodeURIComponent(divId)}?category=${encodeURIComponent(cat)}&limit=${limit}`);
                const data = await res.json();
                if (res.ok && data.status === 'success') {
                    cachedDivisions[cacheKey] = data;
                    renderDivisionData(data);
                } else {
                    if (tbody) tbody.innerHTML = `<tr><td colspan="7" class="py-6 text-center text-rose-400 text-xs">${data.error || 'Failed to load division leaderboard.'}</td></tr>`;
                }
            } catch (err) {
                console.error('Failed to load division leaderboard', err);
                if (tbody) tbody.innerHTML = '<tr><td colspan="7" class="py-6 text-center text-rose-400 text-xs">Network error while retrieving division records.</td></tr>';
            }
        }

        function renderDivisionData(data) {
            const divInfo = data.division || {};
            const list = data.leaderboard || [];
            const cat = data.category || 'qso';
            const limit = data.limit || 10;

            const podiumEl = document.getElementById('continentsPodium');
            const tbody = document.getElementById('continentsTableBody');
            const metaEl = document.getElementById('contMetaInfo');
            const titleEl = document.getElementById('contTableTitle');
            const countEl = document.getElementById('contTableCount');

            if (metaEl) {
                metaEl.textContent = `${divInfo.icon || '🌍'} ${divInfo.name || ''} · ${divInfo.country_count || 0} Countries · ${(divInfo.total_operators || 0).toLocaleString()} Operators`;
            }
            if (titleEl) {
                titleEl.innerHTML = `<span>🏆</span> ${escapeHtml(divInfo.name || '')} Top ${limit}`;
            }
            if (countEl) {
                countEl.textContent = `${list.length} stations`;
            }

            // Render Podium for top 3
            if (podiumEl) {
                podiumEl.innerHTML = '';
                const top3 = list.slice(0, 3);
                const order = top3.length === 3 ? [top3[1], top3[0], top3[2]] : top3;
                order.forEach(item => {
                    if (!item) return;
                    const isFirst = item.rank_in_division === 1;
                    const isSecond = item.rank_in_division === 2;
                    const medal = isFirst ? '👑 🥇' : (isSecond ? '🥈' : '🥉');
                    const podiumClass = isFirst ? 'podium-1' : (isSecond ? 'podium-2' : 'podium-3');
                    const flagSrc = item.flag_url ? `<img src="${item.flag_url}" class="w-6 h-4 object-cover rounded shadow inline-block">` : '';

                    const card = document.createElement('div');
                    card.className = `podium-card ${podiumClass}`;
                    card.innerHTML = `
                        <div class="text-2xl mb-1">${medal}</div>
                        <div class="flex items-center justify-center gap-1.5 mb-1">
                            ${flagSrc}
                            <span class="text-[11px] font-bold text-slate-300 uppercase">${escapeHtml(item.country_name)}</span>
                        </div>
                        <h4 class="text-lg font-black font-mono text-white">${escapeHtml(item.callsign)}</h4>
                        <div class="text-base font-black text-cyan-300 mt-1">${item.score_display}</div>
                        <span class="text-[10px] text-slate-400 block mt-0.5">World: ${escapeHtml(item.world_rank)}</span>
                        <div class="mt-3 flex items-center justify-center gap-1.5">
                            <button data-action="analyze-station" data-callsign="${escapeHtml(item.callsign)}" class="px-2.5 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-cyan-300 text-[10px] font-bold">Inspect</button>
                            <button class="px-2.5 py-1 rounded-lg bg-indigo-950/80 hover:bg-indigo-900 text-indigo-300 text-[10px] font-bold" onclick="launchVersusWith('${escapeHtml(item.callsign)}')">Versus</button>
                        </div>
                    `;
                    podiumEl.appendChild(card);
                });
            }

            // Render Table
            if (tbody) {
                tbody.innerHTML = '';
                list.forEach(item => {
                    const tr = document.createElement('tr');
                    tr.className = 'hover:bg-slate-800/40 transition-colors';
                    const flagSrc = item.flag_url ? `<img src="${item.flag_url}" class="w-5 h-3.5 object-cover rounded shadow inline-block mr-1">` : '';
                    const rankClass = item.rank_in_division <= 3 ? 'text-amber-300 font-bold' : 'text-slate-400';
                    tr.innerHTML = `
                        <td class="py-2.5 px-4 text-center ${rankClass}">#${item.rank_in_division}</td>
                        <td class="py-2.5 px-4 font-bold text-white font-mono flex items-center gap-1">
                            <span>${escapeHtml(item.callsign)}</span>
                            ${item.rank_in_division === 1 ? '<span class="text-[10px] text-amber-400">👑</span>' : ''}
                        </td>
                        <td class="py-2.5 px-4 text-slate-300">
                            <div class="flex items-center gap-1">
                                ${flagSrc}
                                <span>${escapeHtml(item.country_name)}</span>
                            </div>
                        </td>
                        <td class="py-2.5 px-4 text-cyan-300 font-bold">${item.score_display}</td>
                        <td class="py-2.5 px-4 text-slate-400 text-[11px]">${item.score_countries} DXCC · ${item.score_band} Bands</td>
                        <td class="py-2.5 px-4 text-slate-400">${escapeHtml(item.world_rank)}</td>
                        <td class="py-2.5 px-4 text-right space-x-1">
                            <button data-action="analyze-station" data-callsign="${escapeHtml(item.callsign)}" class="px-2.5 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-cyan-300 text-[10px] font-bold">Inspect</button>
                            <button class="px-2 py-1 rounded-lg bg-indigo-950 hover:bg-indigo-900 text-indigo-300 text-[10px] font-bold" onclick="launchVersusWith('${escapeHtml(item.callsign)}')">⚔️</button>
                        </td>
                    `;
                    tbody.appendChild(tr);
                });
            }
        }

        function launchVersusWith(callsign) {
            switchTab('versus');
            const inp2 = document.getElementById('vsCallsign2');
            const inp1 = document.getElementById('vsCallsign1');
            if (inp1 && !inp1.value.trim()) {
                inp1.value = callsign;
            } else if (inp2) {
                inp2.value = callsign;
                startVersusMatch();
            }
        }

'''

if 'STANDOUT FEATURE 4' not in content:
    js_end_anchor = '// Tab button for versus'
    content = content.replace(js_end_anchor, js_div_controller + js_end_anchor, 1)
    print('[OK] Added Division Leaderboard JS controller.')

# 7. Add Division Listeners to JS End
js_listeners_addition = '''        // Tab button for continents
        document.getElementById('tabBtnContinents')?.addEventListener('click', () => switchTab('continents'));

        // Continent Division Pills Listeners
        document.querySelectorAll('.cont-div-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.cont-div-btn').forEach(b => {
                    b.classList.remove('bg-emerald-600', 'border-emerald-500', 'text-white', 'shadow-lg', 'shadow-emerald-600/20');
                    b.classList.add('bg-slate-900/80', 'border-slate-700/60', 'text-slate-300');
                });
                btn.classList.remove('bg-slate-900/80', 'border-slate-700/60', 'text-slate-300');
                btn.classList.add('bg-emerald-600', 'border-emerald-500', 'text-white', 'shadow-lg', 'shadow-emerald-600/20');
                currentDivisionId = btn.dataset.div;
                loadDivisionLeaderboard();
            });
        });

        // Continent Category Buttons
        document.querySelectorAll('.cont-cat-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.cont-cat-btn').forEach(b => {
                    b.classList.remove('bg-emerald-600', 'text-white');
                    b.classList.add('text-slate-400');
                });
                btn.classList.remove('text-slate-400');
                btn.classList.add('bg-emerald-600', 'text-white');
                currentDivisionCategory = btn.dataset.cat;
                loadDivisionLeaderboard();
            });
        });

        // Continent Limit Buttons
        document.querySelectorAll('.cont-limit-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.cont-limit-btn').forEach(b => {
                    b.classList.remove('bg-slate-800', 'text-emerald-300');
                    b.classList.add('text-slate-400');
                });
                btn.classList.remove('text-slate-400');
                btn.classList.add('bg-slate-800', 'text-emerald-300');
                currentDivisionLimit = parseInt(btn.dataset.limit) || 10;
                loadDivisionLeaderboard();
            });
        });
'''

if "document.getElementById('tabBtnContinents')" not in content:
    tab_target = "document.getElementById('tabBtnVersus')?.addEventListener('click', () => switchTab('versus'));"
    content = content.replace(tab_target, js_listeners_addition + tab_target, 1)
    print('[OK] Added event listeners for Continents tab and division controls.')

# 8. Update URL params handling for continents
url_param_old = "const urlVs = urlParams.get('vs');"
url_param_new = '''const urlDivision = urlParams.get('division') || urlParams.get('div');
        if (urlDivision && ['me', 'eu', 'as', 'af', 'na', 'sa', 'oc'].includes(urlDivision.toLowerCase())) {
            currentDivisionId = urlDivision.toLowerCase();
            switchTab('continents');
            document.querySelectorAll('.cont-div-btn').forEach(b => {
                const isMatch = b.dataset.div === currentDivisionId;
                b.classList.toggle('active', isMatch);
                if (isMatch) {
                    b.classList.add('bg-emerald-600', 'border-emerald-500', 'text-white', 'shadow-lg');
                    b.classList.remove('bg-slate-900/80', 'border-slate-700/60', 'text-slate-300');
                } else {
                    b.classList.remove('bg-emerald-600', 'border-emerald-500', 'text-white', 'shadow-lg');
                    b.classList.add('bg-slate-900/80', 'border-slate-700/60', 'text-slate-300');
                }
            });
        }
        const urlVs = urlParams.get('vs');'''

if url_param_old in content and 'urlDivision' not in content:
    content = content.replace(url_param_old, url_param_new, 1)
    print('[OK] Added URL query parameter support for ?division=...')

# 9. Update station analysis render in fetchStationAnalysis and openStationModal to show continental rank
nat_summary_old = "natSummary.innerText = ns.country_rank_qso \n                        ? `#${ns.country_rank_qso} in ${data.country_name || 'Country'} (${(data.country_iso || '').toUpperCase()})` \n                        : `Unranked in ${data.country_name || 'Country'}`;"

nat_summary_new = '''const cs = data.continental_standing || {};
                let extraDivText = '';
                if (cs.region_rank_qso) {
                    extraDivText += ` · #${cs.region_rank_qso} in ${cs.region_name} (${cs.region_icon || '🕌'})`;
                } else if (cs.continent_rank_qso) {
                    extraDivText += ` · #${cs.continent_rank_qso} in ${cs.continent_name} (${cs.continent_icon || '🌍'})`;
                }
                natSummary.innerText = ns.country_rank_qso 
                    ? `#${ns.country_rank_qso} in ${data.country_name || 'Country'} (${(data.country_iso || '').toUpperCase()})${extraDivText}` 
                    : `Unranked in ${data.country_name || 'Country'}`;'''

if nat_summary_old in content:
    content = content.replace(nat_summary_old, nat_summary_new, 1)
    print('[OK] Updated natSummary in fetchStationAnalysis to display continental rank.')

modal_nat_summary_old = "natSummary.innerText = anData.national_rank_qso \n                                ? `#${anData.national_rank_qso} in ${anData.country_name || 'Country'} (${(anData.country_iso || '').toUpperCase()})` \n                                : `Unranked in ${anData.country_name || 'Country'}`;"

modal_nat_summary_new = '''const mcs = anData.continental_standing || {};
                            let mExtraDiv = '';
                            if (mcs.region_rank_qso) {
                                mExtraDiv += ` · #${mcs.region_rank_qso} in ${mcs.region_name} (${mcs.region_icon || '🕌'})`;
                            } else if (mcs.continent_rank_qso) {
                                mExtraDiv += ` · #${mcs.continent_rank_qso} in ${mcs.continent_name} (${mcs.continent_icon || '🌍'})`;
                            }
                            natSummary.innerText = anData.national_rank_qso 
                                ? `#${anData.national_rank_qso} in ${anData.country_name || 'Country'} (${(anData.country_iso || '').toUpperCase()})${mExtraDiv}` 
                                : `Unranked in ${anData.country_name || 'Country'}`;'''

if modal_nat_summary_old in content:
    content = content.replace(modal_nat_summary_old, modal_nat_summary_new, 1)
    print('[OK] Updated modalNatStandingSummary to display continental rank.')

# 10. Add Backend Flask Endpoints for divisions
backend_div_routes = '''@app.route('/api/v1/divisions', methods=['GET'])
@app.route('/api/divisions', methods=['GET'])
def api_divisions_list():
    cache_key = "qrz:divisions:list"
    cached = cache_get(cache_key)
    if cached:
        return jsonify(cached), 200

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        divisions_data = []
        for div_id, info in CONTINENT_DIVISIONS.items():
            tot = get_division_operator_total(cursor, info['countries'])
            divisions_data.append({
                'id': info['id'],
                'name': info['name'],
                'name_fa': info['name_fa'],
                'icon': info['icon'],
                'description': info['description'],
                'country_count': len(info['countries']),
                'total_operators': tot
            })
        payload = {'status': 'success', 'divisions': divisions_data}
        cache_set(cache_key, payload, ttl=7200)
        return jsonify(payload), 200
    finally:
        cursor.close()
        conn.close()

@app.route('/api/v1/leaderboard/division/<string:division_id>', methods=['GET'])
@app.route('/api/leaderboard/division/<string:division_id>', methods=['GET'])
def api_division_leaderboard(division_id):
    div_id = division_id.strip().lower()
    if div_id not in CONTINENT_DIVISIONS:
        return jsonify({"error": f"Division '{division_id}' not found."}), 404

    category = request.args.get('category', 'qso').strip().lower()
    if category not in ['qso', 'countries', 'band']:
        category = 'qso'

    try:
        limit = int(request.args.get('limit', 10))
        if limit not in [10, 25, 50]:
            limit = 10
    except (ValueError, TypeError):
        limit = 10

    cache_key = f"qrz:lb:div:{div_id}:{category}:{limit}"
    cached = cache_get(cache_key)
    if cached:
        return jsonify(cached), 200

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        data = get_division_leaderboard(cursor, div_id, category=category, limit=limit)
        cache_set(cache_key, data, ttl=3600)
        return jsonify(data), 200
    finally:
        cursor.close()
        conn.close()

'''

if 'def api_division_leaderboard(' not in content:
    main_anchor = "if __name__ == '__main__':"
    content = content.replace(main_anchor, backend_div_routes + main_anchor, 1)
    print('[OK] Added Flask routes for divisions and division leaderboards.')

# Write to app.py.new
with open('/opt/qrz-project/app.py.new', 'w', encoding='utf-8') as f:
    f.write(content)

print('[OK] Successfully generated /opt/qrz-project/app.py.new with Feature 4.')
