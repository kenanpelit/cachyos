// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║ margo — init.rhai  (compositor scripting / automation)                    ║
// ║ Location: ~/.config/margo/init.rhai                                       ║
// ╚═══════════════════════════════════════════════════════════════════════════╝
//
// Bu dosya compositor'ın İÇİNDE, event-loop'un ortasında çalışır. Statik
// `windowrule`'ların yapamadığı imperatif otomasyonu sağlar: olaylara tepki
// ver, canlı durumu sorgula, zincirleme `dispatch` yap.
//
// Canlı test (relogin'siz — hook'lar kalıcı olur):
//     mctl run ~/.config/margo/init.rhai
// Her açılışta otomatik yüklenir.
//
// ── API hatırlatma ──────────────────────────────────────────────────────────
//  Sorgu : current_tag() current_tagmask() focused_appid() focused_title()
//          focused_monitor_name() monitor_count() monitor_names() client_count()
//  Aksiyon: dispatch("eylem")  dispatch("eylem",[arg,...])
//          dispatch("spawn",["kabuk komutu"])   // 'spawn' Rhai'de rezerve →
//                                               // helper yerine bu yol kullanılır
//          tag(n) -> n. tag'in bitmask'i      (ör. dispatch("view",[tag(2)]))
//  Hook'lar:
//    on_window_open(||{...})           // açılan pencere o an odakta → focused_appid()
//    on_window_close(|appid,title|{})  // parametre ALIR (kapanan pencere)
//    on_focus_change(||{...})
//    on_tag_switch(||{...})            // current_tag() ile yeni tag'i oku
//    on_output_change(|name|{...})     // monitör tak/çıkar/yeniden tara
//
//  `dispatch(...)` mctl ile aynı eylem yüzeyini kullanır — eylem isimleri ve
//  arg şekilleri için:  mctl actions --verbose

// ── DISCOVERY: app-id'leri keşfet ───────────────────────────────────────────
// Aşağıdaki kuralları yazarken uygulamanın gerçek app-id'si gerek. Açık
// pencereleri app-id + başlık + tag ile listele:
//     mctl clients
// (Ör. senin sistemde: Spotify, webcord, ferdium, TmuxKenp, Helium tabları…)

// ── 1) Belirli uygulamalar açılınca otomatik FLOATING ───────────────────────
// Ayar/seçici tipi küçük pencereler tile'a girmesin, ortada yüzsün.
on_window_open(|| {
    let app = focused_appid();
    if app == "pavucontrol"
        || app == "blueman-manager"
        || app == "nm-connection-editor"
        || app == "org.gnome.Calculator"
    {
        dispatch("togglefloating");
    }
});

// ── 2) Uygulamaya göre LAYOUT ───────────────────────────────────────────────
// Görsel/video açılınca o tag'i monocle'a al (tam ekran tek pencere hissi);
// terminal/editör açılınca scroller'a dön. (Mevcut tag'i değiştirir, pencereyi
// taşımaz — sarsıcı değil.)
on_window_open(|| {
    let app = focused_appid();
    if app == "imv" || app == "mpv" || app.contains("feh") {
        dispatch("setlayout", ["monocle"]);
    } else if app == "kitty" || app.contains("Code") {
        dispatch("setlayout", ["scroller"]);
    }
});

// ── 3) Belirli bir uygulamayı kendi TAG'ine yönlendir (opsiyonel) ────────────
// Klasik "Spotify hep 8. tag'e" kuralı. `tag` pencereyi taşır ama görünümde
// kalırsın; peşinden gitmek istersen `view` satırının başındaki // 'ı kaldır.
// on_window_open(|| {
//     if focused_appid() == "Spotify" {
//         dispatch("tag",  [tag(8)]);
//         // dispatch("view", [tag(8)]);   // pencereyle birlikte 8. tag'e geç
//     }
// });

// ── 4) MONİTÖR tak/çıkar bildirimi ──────────────────────────────────────────
// Harici monitör bağlanınca/çıkınca görsel geri bildirim — mevcut monitör
// sayısını gösterir. (name şimdilik boş gelebilir; sayım güvenilir kanal.)
on_output_change(|name| {
    let n = monitor_count();
    dispatch("spawn", ["notify-send 'margo' 'Monitör düzeni değişti — aktif: " + n.to_string() + "'"]);
});

// ── 5) Pencere kapanınca (parametre ALAN hook örneği) ────────────────────────
// Son pencere de kapanıp masaüstü boşaldıysa scroller'a dön.
on_window_close(|appid, title| {
    if client_count() <= 1 {
        dispatch("setlayout", ["scroller"]);
    }
});
