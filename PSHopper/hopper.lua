-- ============================================================
-- PS HOPPER TOOL v4.0 — SERVER FILLER
-- Single file, single process (inline)
-- Target: Termux + Root Android
-- Fitur: Auto-fill 8 alt ke beberapa PS, monitoring, re-fill DC
-- ============================================================

local W = 50
local ACTIVITY = "com.roblox.client.startup.ActivitySplash"

-- Folder rapi di /sdcard/PSHopper/
local DIR = "/sdcard/PSHopper"
local PS_FILE_PATH = DIR .. "/private_servers.txt"
local COOKIE_FILE = DIR .. "/roblox_cookie.txt"
local HOPPER_LOG = DIR .. "/hopper_log.txt"
local README_FILE = DIR .. "/README.txt"

-- Config server filler
local DEFAULT_DELAY = 20
local LAYOUT_DELAY = 10
local WATCHDOG_SEC = 10
local CHECK_INTERVAL = 120   -- cek API tiap 2 menit
local TARGET_ALTS = 8        -- target alt per server (hopper tidak dihitung)
local ALT_COUNT = 8          -- jumlah alt account di HP

-- ============================================================
-- UTIL DASAR
-- ============================================================
local function sleep(s) if s and s > 0 then os.execute("sleep "..tostring(s)) end end

local function clean(str)
    if not str then return "-" end
    str = str:gsub("\27%[[%d;]*[A-Za-z]",""):gsub("[\r\n\t]",""):gsub("%c","")
    str = str:gsub("^%s+",""):gsub("%s+$","")
    return str ~= "" and str or "-"
end

local function sanitize_pkg(p)
    if not p then return nil end
    local s = p:gsub("[^%w%._]","")
    return s ~= "" and s or nil
end

local function is_valid_ps_link(l)
    if not l or l == "" then return false end
    if not l:match("^https?://") and not l:match("^intent://") then return false end
    if not l:lower():match("code=") then return false end
    if l:match("[;|`$%(%){}%z]") then return false end
    return true
end

local function trunc(s, m)
    if not s then return "-" end
    if #s <= m then return s end
    return m > 2 and (s:sub(1,m-2).."..") or s:sub(1,m)
end

local function parse_selection(input, max)
    local sel, seen = {}, {}
    local a, b = input:match("^(%d+)%-(%d+)$")
    if a and b then
        for i = tonumber(a), tonumber(b) do
            if i>=1 and i<=max and not seen[i] then table.insert(sel,i); seen[i]=true end
        end
        return sel
    end
    for n in input:gmatch("(%d+)") do
        local v = tonumber(n)
        if v and v>=1 and v<=max and not seen[v] then table.insert(sel,v); seen[v]=true end
    end
    return sel
end

-- UI helpers
local function color(c) io.write("\27["..c.."m"); io.flush() end
local function noreset() io.write("\27[0m"); io.flush() end
local function cls() io.write("\27[2J\27[3J\27[H\27[0m"); io.flush() end
local function border() print(string.rep("-",W)) end

local function box_title(t)
    local inner = math.max(W-2, #t+2)
    local pl = math.floor((inner-#t)/2)
    local pr = inner - #t - pl
    print("+"..string.rep("-",inner).."+")
    print("|"..string.rep(" ",pl)..t..string.rep(" ",pr).."|")
    print("+"..string.rep("-",inner).."+")
end

local function info(l, v)
    local p = l..": "
    print(p..trunc(v, math.max(W-#p,4)))
end

local function print_logo()
    color("36")
    print([[ ░▒▓███████▓▒░▒▓████████▓▒░▒▓█▓▒░▒▓████████▓▒░
░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░
░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░    ░▒▓██▓▒░ 
 ░▒▓██████▓▒░░▒▓██████▓▒░ ░▒▓█▓▒░  ░▒▓██▓▒░   
       ░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓██▓▒░     
       ░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░▒▓█▓▒░       
░▒▓███████▓▒░░▒▓████████▓▒░▒▓█▓▒░▒▓████████▓▒░]])
    noreset(); print("")
end

-- INPUT
local function ask(prompt)
    io.write(prompt.." > "); io.flush()
    local tty = io.open("/dev/tty","r")
    local r
    if tty then r = tty:read("*l"); tty:close() else r = io.read("*l") end
    if r == nil then sleep(2) end
    return r
end

local function read_key(t)
    local h = io.popen("bash -c 'read -t "..(t or 1).." -n 1 k < /dev/tty 2>/dev/null && echo $k' 2>/dev/null")
    if not h then sleep(t or 1); return nil end
    local k = h:read("*l"); h:close()
    return (k and k ~= "") and k or nil
end

-- SYSTEM (root)
local function su_cmd(cmd)
    local h = io.popen("su -c '"..cmd:gsub("'","'\\''").."' 2>&1")
    if not h then return "ERROR" end
    local r = h:read("*a"); h:close()
    return clean(r)
end

local function su_exec(cmd)
    os.execute("su -c '"..cmd:gsub("'","'\\''").."' >/dev/null 2>&1")
end

-- ============================================================
-- SETUP FOLDER (auto-create saat pertama run)
-- ============================================================
local function ensure_folder()
    os.execute("mkdir -p '"..DIR.."' 2>/dev/null")
    -- buat private_servers.txt jika belum ada
    local f = io.open(PS_FILE_PATH,"r")
    if not f then
        local d = io.open(PS_FILE_PATH,"w")
        if d then
            d:write("https://www.roblox.com/games/123456?privateServerLinkCode=CONTOH1\n")
            d:write("https://www.roblox.com/games/123456?privateServerLinkCode=CONTOH2\n")
            d:close()
        end
    else f:close() end
    -- buat roblox_cookie.txt jika belum ada
    local c = io.open(COOKIE_FILE,"r")
    if not c then
        local d = io.open(COOKIE_FILE,"w")
        if d then d:write(""); d:close() end
    else c:close() end
    -- buat README.txt jika belum ada
    local r = io.open(README_FILE,"r")
    if not r then
        local d = io.open(README_FILE,"w")
        if d then
            d:write("PS HOPPER TOOL v4.0 - SERVER FILLER\n")
            d:write("===================================\n\n")
            d:write("File penting:\n")
            d:write("  private_servers.txt = daftar link PS (1 per baris)\n")
            d:write("  roblox_cookie.txt   = cookie .ROBLOSECURITY akun pemilik PS\n")
            d:write("  hopper_log.txt      = log otomatis (dibuat saat run)\n\n")
            d:write("Cara run:\n")
            d:write("  termux-wake-lock\n")
            d:write("  lua /sdcard/PSHopper/hopper.lua\n\n")
            d:write("Butuh root + jq + curl\n")
            d:write("  pkg install jq curl\n")
            d:close()
        end
    else r:close() end
end

-- ============================================================
-- DETECTION
-- ============================================================
local function detect_offset()
    local off = 0
    local st = su_cmd("dumpsys window | grep mStable | head -1")
    local v = st:match("mStable=%[%d+,(%d+)%]")
    if v then off = tonumber(v) or 0 end
    if off == 0 then
        local d = su_cmd("wm density"):match("(%d+)")
        off = d and math.ceil(24*tonumber(d)/160) or 48
    end
    return off
end

local function detect_screen()
    local off = detect_offset()
    local r = su_cmd("wm size")
    local sw, sh = r:match("(%d+)x(%d+)")
    if not sw then return nil,nil,off,r end
    sw, sh = tonumber(sw), tonumber(sh)
    return math.min(sw,sh), math.max(sw,sh), off, nil
end

local function detect_packages()
    local h = io.popen("pm list packages | grep com.roblox.")
    if not h then return {} end
    local r = h:read("*a") or ""; h:close()
    local pkgs = {}
    for line in r:gmatch("[^\r\n]+") do
        local p = line:match("package:(.+)")
        if p then p = sanitize_pkg(clean(p)); if p then table.insert(pkgs,p) end end
    end
    return pkgs
end

-- ============================================================
-- LAYOUT
-- ============================================================
local function apply_layout(pkg, L, T, R, B)
    local pref = "/data/data/"..pkg.."/shared_prefs/"..pkg.."_preferences.xml"
    su_exec("chmod 666 "..pref)
    local args = {}
    for _, f in ipairs({
        {"app_cloner_current_window_left",L},{"app_cloner_current_window_top",T},
        {"app_cloner_current_window_right",R},{"app_cloner_current_window_bottom",B},
    }) do
        table.insert(args, "-e 's/name=\\\""..f[1].."\\\" value=\\\"[^\\\"]*\\\"/name=\\\""..f[1].."\\\" value=\\\""..f[2].."\\\"/g'")
    end
    su_exec("sed -i "..table.concat(args," ").." "..pref)
    su_exec("chmod 444 "..pref)
end

local function grid_h(n, sh, off) return math.floor((sh-off)/n) end

local function grid_bounds(i, n, sw, sh, off)
    if n == 1 then return 0,0,sw,sh end
    local gh = grid_h(n,sh,off); local row = i-1
    return 0, (row*gh)+off, sw, ((row+1)*gh)+off
end

-- ============================================================
-- LOGGING
-- ============================================================
local function hlog(msg)
    local f = io.open(HOPPER_LOG,"a")
    if f then f:write(os.date("%H:%M:%S ") .. msg .. "\n"); f:close() end
end

local function is_running(pkg)
    local h = io.popen("su -c 'pidof "..pkg.."' 2>/dev/null")
    if not h then return false end
    local r = h:read("*a") or ""; h:close()
    return r:match("%d+") ~= nil
end

local function launch_client(c, ps_list, ps_idx, cnum)
    if not ps_list[ps_idx] then hlog("ERROR: PS "..tostring(ps_idx).." OOB"); return end
    su_exec("am force-stop "..c.pkg); sleep(1)
    local raw = ps_list[ps_idx]
    local dp = raw:match("^intent://(.-)#Intent") or raw:gsub("^https?://","")
    local intent = "intent://"..dp.."#Intent;scheme=https;package="..c.pkg..";action=android.intent.action.VIEW;end"
    su_exec('am start --user 0 "'..intent..'"')
    hlog("Client "..cnum.." -> PS "..ps_idx)
end

-- ============================================================
-- API ROBLOX — DETEKSI PLAYER
-- ============================================================
local universe_cache = {}

local function load_cookie()
    local f = io.open(COOKIE_FILE,"r")
    if not f then return nil end
    local c = f:read("*a"); f:close()
    c = clean(c)
    if c == "" or c == "-" then return nil end
    return c
end

-- Parse placeId dari URL: "https://www.roblox.com/games/123456/Name?code=XXX" -> 123456
local function extract_place_id(url)
    if not url then return nil end
    local pid = url:match("/games/(%d+)")
    if not pid then
        pid = url:match("placeId=(%d+)")
    end
    return pid and tonumber(pid) or nil
end

-- placeId -> universeId (cached, 1x query per game)
local function get_universe_id(pid)
    if universe_cache[pid] then return universe_cache[pid] end
    local h = io.popen("curl -s 'https://apis.roblox.com/universes/v1/places/"..pid.."/universe' 2>/dev/null")
    if not h then return nil end
    local r = h:read("*a") or ""; h:close()
    local uid = r:match('"universeId":(%d+)')
    if uid then
        universe_cache[pid] = tonumber(uid)
    end
    return universe_cache[pid]
end

-- Query VipServer list -> return array {playing=, maxPlayers=}
local function get_ps_players(uid, cookie)
    local cmd = "curl -s -H 'Cookie: .ROBLOSECURITY="..cookie.."' "..
        "'https://games.roblox.com/v1/games/"..uid.."/servers/VipServer?limit=100' 2>/dev/null"
    local h = io.popen(cmd)
    if not h then return nil end
    local r = h:read("*a") or ""; h:close()
    if r:match("401") or r:match("Unauthorized") or r:match("Authorization") then
        return "AUTH_FAIL"
    end
    local servers = {}
    -- parse "playing":N dan "maxPlayers":N berpasangan
    for playing, maxp in r:gmatch('"playing":(%d+)%s*,%s*"maxPlayers":(%d+)') do
        table.insert(servers, {playing=tonumber(playing), max=tonumber(maxp)})
    end
    return servers
end

-- Cek player count per link PS
-- return: {link_index=, placeId=, universeId=, playing=, max=, status=}
local function check_all_servers(ps_list, cookie)
    local results = {}
    if not cookie then return results end
    for i, link in ipairs(ps_list) do
        local pid = extract_place_id(link)
        local playing, maxp, status = nil, nil, "NO_DATA"
        if pid then
            local uid = get_universe_id(pid)
            if uid then
                local sv = get_ps_players(uid, cookie)
                if sv == "AUTH_FAIL" then
                    status = "AUTH_FAIL"
                elseif sv and #sv > 0 then
                    -- ambil server pertama yang cocok dengan game ini
                    playing = sv[1].playing
                    maxp = sv[1].max
                    status = "OK"
                end
            end
        end
        table.insert(results, {
            link_index=i, placeId=pid, playing=playing, max=maxp, status=status
        })
    end
    return results
end

-- Cari server yang kurang dari TARGET_ALTS (tidak termasuk yang AUTH_FAIL)
local function find_underfilled(results, target)
    local list = {}
    for _, r in ipairs(results) do
        if r.status == "OK" and r.playing and r.playing < target then
            table.insert(list, r)
        end
    end
    return list
end

-- ============================================================
-- MENU 1: SET LAYOUT
-- ============================================================
local function set_layout_roblox()
    cls(); color("33"); box_title("SET LAYOUT ROBLOX"); noreset(); print("")
    color("36"); print("Detecting..."); noreset()
    local sw, sh, off, err = detect_screen()
    if not sw then
        color("31"); print("Gagal baca resolusi!")
        if err then print("Output: "..trunc(err,W-8)) end
        noreset(); print(""); ask("Enter"); return
    end
    local pkgs = detect_packages(); local tot = #pkgs
    if tot == 0 then color("31"); print("Tidak ada Roblox!"); noreset(); print(""); ask("Enter"); return end
    border(); color("36")
    info("Packages  ", tostring(tot)); info("Resolusi  ", sw.." x "..sh)
    info("Offset    ", off.." px"); info("Grid      ", "1 x "..tot)
    info("Delay/akun", LAYOUT_DELAY.." dtk"); noreset(); border()
    print(""); print("Offset "..off.."px auto.")
    local adj = ask("Ubah offset? (kosong=skip)")
    if adj and adj ~= "" then
        local no = tonumber(adj)
        if no and no >= 0 then off = no; print("Offset: "..off.."px") else print("Invalid") end
    end
    print(""); color("32"); print("Package:"); noreset()
    for i, p in ipairs(pkgs) do print(" "..i..". "..trunc(p,W-5)) end
    print("")
    local c = ask("Lanjut? (y/n)")
    if not c or c:lower() ~= "y" then print("Batal."); sleep(1); return end
    print(""); border(); color("33"); print("Setup layout..."); noreset(); print("")
    for i = 1, tot do
        local p = pkgs[i]; local L,T,R,B = grid_bounds(i,tot,sw,sh,off)
        color("36"); print("["..i.."/"..tot.."] "..trunc(p,W-8)); noreset()
        su_exec("am force-stop "..p); apply_layout(p,L,T,R,B)
        su_exec("am start --user 0 -n "..p.."/"..ACTIVITY)
        print("  L="..L.." T="..T.." R="..R.." B="..B)
        if i < tot then print("  Tunggu "..LAYOUT_DELAY.."s..."); sleep(LAYOUT_DELAY) end
    end
    print(""); border(); color("32"); print("SELESAI!"); noreset(); border(); print("")
    local cl = ask("Close semua? (y/n)")
    if cl and cl:lower() == "y" then
        for _,p in ipairs(pkgs) do su_exec("am force-stop "..p) end
        color("32"); print(tot.." ditutup."); noreset()
    end
    print(""); ask("Enter")
end

-- ============================================================
-- MENU 2: SERVER FILLER
-- ============================================================
local function load_ps_links()
    local f = io.open(PS_FILE_PATH,"r")
    if not f then return nil, 0 end
    local list, skip = {}, 0
    for line in f:lines() do
        local l = line:gsub("%c",""):gsub("%s+","")
        if l:lower():match("code=") then
            if is_valid_ps_link(l) then table.insert(list,l) else skip=skip+1 end
        end
    end
    f:close()
    return list, skip
end

-- Render monitor server filler
local function render_filler(ps_list, results, phase, done_count, status)
    cls()
    color("33"); box_title("SERVER FILLER MONITOR"); noreset(); print("")
    if phase == "filling" then
        color("36"); print(" FASE: FILLING ("..done_count.."/"..#ps_list.." server done)"); noreset()
    else
        color("36"); print(" FASE: MONITORING (semua full)"); noreset()
    end
    print("")
    color("32"); print(" PS#  Alts    Status      Keterangan"); noreset()
    print(string.rep("-",W))
    for i, r in ipairs(results) do
        local alt = r.playing or "?"
        local maxv = r.max or "?"
        local line
        if r.status == "AUTH_FAIL" then
            color("31"); line = string.format(" %-3d  %-6s  %-10s  Cookie invalid/expired", i, alt.."/"..maxv, "✖ AUTH")
        elseif r.status == "NO_DATA" then
            color("90"); line = string.format(" %-3d  %-6s  %-10s  Tidak ada data", i, "-", "○ NO DATA")
        elseif r.playing and r.playing >= TARGET_ALTS then
            color("32"); line = string.format(" %-3d  %-6s  %-10s  FULL", i, alt.."/"..maxv, "✅ FULL")
        elseif r.playing and r.playing > 0 then
            color("33"); line = string.format(" %-3d  %-6s  %-10s  Kurang "..(TARGET_ALTS-r.playing).." alt", i, alt.."/"..maxv, "🔄 FILLING")
        else
            color("90"); line = string.format(" %-3d  %-6s  %-10s  Kosong", i, alt.."/"..maxv, "⏳ PENDING")
        end
        print(line); noreset()
    end
    print(""); border(); color("36")
    print("  Interval: "..(CHECK_INTERVAL/60).." menit | Target: "..TARGET_ALTS.." alt")
    print("  Waktu: "..os.date("%H:%M:%S"))
    print("  Status: "..(status or "RUNNING"))
    noreset(); border(); print("")
    color("33"); print("  Tekan [q] untuk Stop & Reset"); noreset()
end

local function menu_server_filler()
    cls(); color("33"); box_title("SERVER FILLER"); noreset(); print("")
    -- 1. Package
    color("36"); print("Mencari Roblox..."); noreset()
    local pkgs = detect_packages(); local tot = #pkgs
    if tot == 0 then color("31"); print("Tidak ada Roblox!"); noreset(); print(""); ask("Enter"); return end
    print("Ditemukan "..tot.." client:")
    for i,p in ipairs(pkgs) do print("  "..i..". "..trunc(p,W-6)) end
    border(); print("")
    -- 2. PS links
    local ps_list, skip = load_ps_links()
    if not ps_list then color("31"); print("File PS tidak ada!"); noreset(); print(""); ask("Enter"); return end
    if skip > 0 then color("33"); print(skip.." link invalid dilewati"); noreset() end
    if #ps_list == 0 then color("31"); print("Tidak ada link valid!"); noreset(); print(""); ask("Enter"); return end
    color("32"); print(#ps_list.." link PS valid."); noreset(); print("")
    -- 3. Cookie
    local cookie = load_cookie()
    if not cookie then
        color("31"); print("Cookie TIDAK ada! Deteksi player nonaktif."); noreset()
        print("Isi: "..COOKIE_FILE); print("")
        local cc = ask("Lanjut tanpa cookie? (y/n)")
        if not cc or cc:lower() ~= "y" then print("Batal."); sleep(1); return end
    else
        color("32"); print("Cookie: ✓ ditemukan"); noreset()
    end
    print("")
    -- 4. Pilih hopper
    print("Pilih akun HOPPER (1 akun utama):"); print("")
    local si = ask("Hopper = client nomor")
    if not si or si == "" then print("Batal."); sleep(1); return end
    local hop_idx = tonumber(si)
    if not hop_idx or hop_idx < 1 or hop_idx > tot then color("31"); print("Invalid!"); noreset(); print(""); ask("Enter"); return end
    local hopper_pkg = pkgs[hop_idx]
    -- 5. Pilih alt
    print(""); print("Pilih ALT account (sisanya, cth: 1,2,3 / 1-8):"); print("")
    local ai = ask("Alt = client")
    if not ai or ai == "" then print("Batal."); sleep(1); return end
    local alt_sel = parse_selection(ai, tot)
    if #alt_sel == 0 then color("31"); print("Invalid!"); noreset(); print(""); ask("Enter"); return end
    -- remove hopper dari list alt jika ada
    local alt_list = {}
    for _, idx in ipairs(alt_sel) do
        if idx ~= hop_idx then table.insert(alt_list, pkgs[idx]) end
    end
    if #alt_list == 0 then color("31"); print("Tidak ada alt valid!"); noreset(); print(""); ask("Enter"); return end
    color("36"); print("Hopper: "..trunc(hopper_pkg,W-9).." | Alt: "..#alt_list.." akun"); noreset()
    -- 6. Preview
    print(""); border(); color("36")
    info("Total PS", tostring(#ps_list))
    info("Hopper  ", "#"..hop_idx.." ("..trunc(hopper_pkg,W-10)..")")
    info("Alt     ", #alt_list.." akun")
    info("Target  ", TARGET_ALTS.." alt/server")
    info("Interval", (CHECK_INTERVAL/60).." menit")
    noreset(); border(); print("")
    local cf = ask("Launch? (y/n)")
    if not cf or cf:lower() ~= "y" then print("Batal."); sleep(1); return end
    print(""); color("33"); print("Preparing..."); noreset(); print("")
    -- 7. Screen + layout
    local sw, sh, off, se = detect_screen()
    if not sw then color("31"); print("Gagal resolusi!"); noreset(); ask("Enter"); return end
    local total_clients = 1 + #alt_list
    local all_clients = {hopper_pkg}
    for _, a in ipairs(alt_list) do table.insert(all_clients, a) end
    for i, p in ipairs(all_clients) do
        local L,T,R,B = grid_bounds(i, total_clients, sw, sh, off)
        su_exec("am force-stop "..p); apply_layout(p,L,T,R,B)
    end
    -- 8. Clear log
    su_exec("rm -f "..HOPPER_LOG.." 2>/dev/null")
    hlog("--- Server Filler Started ---")
    -- 9. FASE 1: FILLING
    local done = 0
    local quit = false
    local results = {}
    if cookie then results = check_all_servers(ps_list, cookie) end
    for link_i = 1, #ps_list do
        if quit then break end
        -- cek apakah link ini sudah full
        local cur = results[link_i]
        if cur and cur.status == "OK" and cur.playing and cur.playing >= TARGET_ALTS then
            done = done + 1
            render_filler(ps_list, results, "filling", done, "FULL, skip")
            continue_ok = true
        else
            -- launch hopper + alt ke PS ini
            hlog("Fill PS "..link_i)
            -- hopper masuk
            launch_client({pkg=hopper_pkg}, ps_list, link_i, 0)
            sleep(2)
            -- alt masuk satu per satu
            for ai, apkg in ipairs(alt_list) do
                launch_client({pkg=apkg}, ps_list, link_i, ai)
                if ai < #alt_list then sleep(DEFAULT_DELAY) end
            end
            -- tunggu sampai full (cek API tiap CHECK_INTERVAL)
            local filled = false
            local wait_start = os.time()
            while not filled and not quit do
                if cookie then results = check_all_servers(ps_list, cookie) end
                render_filler(ps_list, results, "filling", done, "Menunggu alt...")
                local key = read_key(1)
                if key and key:lower() == "q" then quit = true; break end
                local r = results[link_i]
                if r and r.status == "OK" and r.playing and r.playing >= TARGET_ALTS then
                    filled = true
                    done = done + 1
                    hlog("PS "..link_i.." FULL ("..r.playing.." alt)")
                else
                    sleep(1)
                end
            end
        end
    end
    -- 10. FASE 2: MONITORING + RE-FILL
    if not quit and done >= #ps_list then
        render_filler(ps_list, results, "monitoring", done, "Semua full")
        print(""); color("32"); print("Semua server FULL! Masuk fase monitoring."); noreset()
        sleep(2)
    end
    while not quit do
        if cookie then results = check_all_servers(ps_list, cookie) end
        render_filler(ps_list, results, "monitoring", done, "Monitoring...")
        local key = read_key(1)
        if key and key:lower() == "q" then quit = true; break end
        -- cari server yang kurang
        local under = find_underfilled(results, TARGET_ALTS)
        if #under > 0 then
            local r = under[1]
            hlog("Re-fill PS "..r.link_index.." ("..(r.playing or 0).."/"..TARGET_ALTS..")")
            -- hopper masuk dulu
            launch_client({pkg=hopper_pkg}, ps_list, r.link_index, 0)
            sleep(2)
            for ai, apkg in ipairs(alt_list) do
                launch_client({pkg=apkg}, ps_list, r.link_index, ai)
                if ai < #alt_list then sleep(DEFAULT_DELAY) end
            end
            -- tunggu sampai full lagi
            local filled = false
            while not filled and not quit do
                if cookie then results = check_all_servers(ps_list, cookie) end
                render_filler(ps_list, results, "monitoring", done, "Re-fill PS "..r.link_index.."...")
                local k2 = read_key(1)
                if k2 and k2:lower() == "q" then quit = true; break end
                local rr = results[r.link_index]
                if rr and rr.status == "OK" and rr.playing and rr.playing >= TARGET_ALTS then
                    filled = true
                    hlog("PS "..r.link_index.." FULL lagi ("..rr.playing.." alt)")
                else
                    sleep(1)
                end
            end
        else
            sleep(CHECK_INTERVAL)
        end
    end
    -- 11. Reset
    render_filler(ps_list, results, "monitoring", done, "STOPPED")
    print(""); border()
    local rst = ask("Reset & close semua Roblox? (y/n)")
    if rst and rst:lower() == "y" then
        print(""); color("33"); print("Resetting..."); noreset()
        for i, p in ipairs(pkgs) do
            local L,T,R,B = grid_bounds(i,tot,sw,sh,off); apply_layout(p,L,T,R,B)
        end
        print("  Layout     : restored ("..tot.." akun)")
        for _, p in ipairs(pkgs) do su_exec("am force-stop "..p) end
        print("  Roblox     : "..tot.." closed")
        su_exec("rm -f "..HOPPER_LOG.." 2>/dev/null")
        print(""); color("32"); print("Reset selesai!"); noreset()
    end
    print(""); ask("Enter")
end

-- ============================================================
-- MENU 3: CEK STATUS SERVER (Manual)
-- ============================================================
local function menu_check_status()
    cls(); color("33"); box_title("CEK STATUS SERVER"); noreset(); print("")
    local cookie = load_cookie()
    if not cookie then
        color("31"); print("Cookie tidak ada!"); noreset()
        print("Isi: "..COOKIE_FILE); print(""); ask("Enter"); return
    end
    local ps_list, skip = load_ps_links()
    if not ps_list or #ps_list == 0 then
        color("31"); print("Tidak ada link PS!"); noreset(); print(""); ask("Enter"); return
    end
    color("36"); print("Cek "..#ps_list.." server..."); noreset(); print("")
    local results = check_all_servers(ps_list, cookie)
    color("32"); print(" PS#  Players    Status"); noreset()
    print(string.rep("-",W))
    for i, r in ipairs(results) do
        if r.status == "AUTH_FAIL" then
            color("31"); print(string.format(" %-3d  %-9s  Cookie invalid/expired", i, "-"))
        elseif r.status == "NO_DATA" then
            color("90"); print(string.format(" %-3d  %-9s  Tidak ada data", i, "-"))
        elseif r.playing and r.playing >= TARGET_ALTS then
            color("32"); print(string.format(" %-3d  %-9s  FULL", i, r.playing.."/"..(r.max or "?")))
        else
            color("33"); print(string.format(" %-3d  %-9s  Kurang "..(TARGET_ALTS-(r.playing or 0)).." alt", i, (r.playing or 0).."/"..(r.max or "?")))
        end
        noreset()
    end
    print(""); border(); print(""); ask("Enter")
end

-- ============================================================
-- MAIN MENU
-- ============================================================
local function show_menu()
    cls(); print_logo()
    color("33"); box_title("LAYOUT & SERVER FILLER"); noreset(); print("")
    color("32"); print("MENU UTAMA"); noreset()
    print("1. Set Layout Roblox")
    print("2. Server Filler (Auto Fill + Monitor)")
    print("3. Cek Status Server (Manual)")
    print("0. Keluar"); print("")
end

local function main_menu()
    while true do
        show_menu()
        local c = ask("Pilih")
        if c == nil then break end
        if c == "1" then set_layout_roblox()
        elseif c == "2" then menu_server_filler()
        elseif c == "3" then menu_check_status()
        elseif c == "0" then cls(); print("Keluar!"); break end
    end
end

-- ============================================================
-- START
-- ============================================================
cls(); print(""); print("Siap! Membuat folder..."); sleep(1)
ensure_folder()
main_menu()
