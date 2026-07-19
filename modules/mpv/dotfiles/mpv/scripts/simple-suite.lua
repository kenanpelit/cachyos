-- simple-suite.lua
--
-- Üç ayrı script'i (SimpleHistory, SimpleBookmark, SmartCopyPaste_II) tek
-- script altında toplar. Üçü de aynı liste motorunu paylaşır; motor eskiden
-- her dosyada birebir tekrar ediyordu.
--
--   ┌─ simple-suite.lua (bu dosya)  ── tek mpv script'i, tek kimlik
--   │
--   ├─ script-modules/simple-suite/engine.lua     paylaşılan liste motoru
--   ├─ script-modules/simple-suite/history.lua    geçmiş
--   ├─ script-modules/simple-suite/bookmark.lua   yer imleri
--   └─ script-modules/simple-suite/clipboard.lua  pano
--
-- Nasıl çalışıyor
-- ---------------
-- Her özellik kendi ortamında (env) çalışır. Motor her ortama ayrı ayrı
-- yüklenir, böylece üç örneğin state'i (o, list_contents, list_cursor, ...)
-- birbirinden tamamen bağımsız kalır. Motor ve gövde dosyaları bu sayede
-- hiç değiştirilmeden, olduğu gibi paylaşılabiliyor.
--
-- Tek script olduğu için üç örnek mpv'nin AYNI tuş-bağlama ad alanını
-- paylaşır ve adlar çakışırdı (üçü de 'open-list', 'move-up', ... üretiyor).
-- Bunu her ortama önek uygulayan bir `mp` proxy'si vererek çözüyoruz:
-- gövdelerdeki ~70 doğrudan mp.add_forced_key_binding çağrısına dokunmadan,
-- tek noktadan. Kullanıcının bastığı tuşlar değişmez; sadece iç bağlama
-- adları 'history-open-list' gibi öneklenir.
--
-- Ayarlar
-- -------
--   script-opts/simple-suite.conf        üçünün ortak ayarları
--   script-opts/SimpleHistory.conf      \
--   script-opts/SimpleBookmark.conf      >  örneğe özel, ortağı ezer
--   script-opts/SmartCopyPaste_II.conf  /

local msg = require 'mp.msg'

local MODULE_DIR = 'script-modules/simple-suite/'

-- Bir parçayı diskten yükle (henüz çalıştırma).
local function load_part(file)
    local path = mp.find_config_file(MODULE_DIR .. file)
    if not path then
        msg.error(MODULE_DIR .. file .. ' bulunamadi')
        return nil
    end
    local chunk, err = loadfile(path)
    if not chunk then
        msg.error(MODULE_DIR .. file .. ' yuklenemedi: ' .. tostring(err))
        return nil
    end
    return chunk
end

-- Tuş bağlama adlarını öneklenmiş hâlde kaydeden `mp` vekili.
-- Diğer her şey gerçek mp'ye düşer (__index).
local function prefixed_mp(prefix)
    local proxy = setmetatable({}, { __index = mp })

    local function wrap(fn)
        return function(key, name, func, opts)
            return fn(key, name and (prefix .. name) or name, func, opts)
        end
    end

    proxy.add_key_binding = wrap(mp.add_key_binding)
    proxy.add_forced_key_binding = wrap(mp.add_forced_key_binding)
    proxy.remove_key_binding = function(name)
        return mp.remove_key_binding(name and (prefix .. name) or name)
    end

    return proxy
end

local engine = load_part('engine.lua')
if not engine then
    msg.error('liste motoru yuklenemedi; simple-suite devre disi')
    return
end

-- Bir özelliği kendi ortamında ayağa kaldır.
local function spawn(body_file, conf_name, prefix)
    local body = load_part(body_file)
    if not body then return end

    local env = setmetatable({}, { __index = _G })
    env.mp = prefixed_mp(prefix)  -- bağlama adları bu örneğe özel
    env.SUITE_CONF = conf_name    -- engine.lua'daki read_list_options bunu okur

    setfenv(engine, env)
    engine()

    setfenv(body, env)
    local ok, err = pcall(body)
    if not ok then
        msg.error(body_file .. ' calistirilamadi: ' .. tostring(err))
    end
end

spawn('history.lua',   'SimpleHistory',     'history-')
spawn('bookmark.lua',  'SimpleBookmark',    'bookmark-')
spawn('clipboard.lua', 'SmartCopyPaste_II', 'clipboard-')
