# margo-osc: modernz + progressbar + pause_indicator_lite birleştirme

**Tarih:** 2026-07-26
**Durum:** Tasarım onaylandı, uygulama planı bekliyor

## Amaç

mpv'deki üç ayrı OSD/UI scriptini tek bir `margo-osc` scripti altında birleştirmek;
mevcut çakışmaları (çift seekbar, çift merkez-pause) gidermek; kullanıcının sevdiği
"oynatırken en altta incecik sürekli çubuk" görünümünü korumak.

## Mevcut durum

| Script | Satır | Rol | Config |
|---|---|---|---|
| `modernz.lua` | 3792 | Tam OSC: seekbar, chapter işaretleri, süreler, başlık, butonlar, thumbnail, volume | `modernz.conf` (ayarlı, ~370 satır) |
| `progressbar.lua` | 2545 | torque-progressbar: alt çubuk (+hover'da genişleyen), sistem saati, merkez pause | YOK (%100 varsayılan) |
| `pause_indicator_lite.lua` | 218 | Ekran ortası pause glyph (+opsiyonel flash play, mute ikonu) | `pause_indicator_lite.conf` |

**Çakışmalar (önceki çok-ajan incelemesinden):**
- modernz ve progressbar **aynı anda iki seekbar** çiziyor (redundant).
- progressbar ve pause_indicator_lite **iki merkez-pause ikonu** üst üste biniyor.
- progressbar'ın `tab`/`c` tuşları zaten input.conf tarafından gölgede (ölü).
- `mpv.conf`'ta `osc=no` → mpv'nin yerleşik OSC'si yüklü değil, yerini modernz alıyor.

**Kilit gerçek:** modernz zaten progressbar'ın yaptığı her şeyi yapıyor — ince alt çubuk
dahil (`persistentprogress`, şu an `no`). progressbar'ın tek benzersiz özelliği sistem
saati (`.`/`,` frame-step mpv'de yerleşik). pause_indicator_lite'ın merkez glyph'i ise
modernz'de olmayan gerçek bir özellik (modernz'de sadece küçük buton ikonu var).

## Kararlar

- **Yaklaşım:** modernz'i birleşik temel yap (fork + entegrasyon). Bundle/loader değil.
- **İsim:** `margo-osc` → `scripts/margo-osc.lua`, `script-opts/margo-osc.conf`.
- **Sistem saati:** taşınmayacak (kullanıcı istemedi).
- **Merkez pause tıkla-duraklat** (`keybind_set=mbtn_left`): **varsayılan kapalı**
  (`keybind_allow=no`). Glyph sadece görsel; tıklamayı modernz yönetir. Böylece
  mbtn_left çakışması baştan çözülür.

## Mimari

### Dosya değişiklikleri

**Oluşturulacak:**
- `scripts/margo-osc.lua` = mevcut `modernz.lua` içeriği, yeniden adlandırılmış +
  sonuna merkez-pause glyph özelliği entegre edilmiş bağımsız blok.
- `script-opts/margo-osc.conf` = mevcut `modernz.conf` + `persistentprogress=yes`
  (ayarlı yükseklik) + yeni "Merkez Pause Göstergesi" ayar bölümü.

**Silinecek:**
- `scripts/progressbar.lua`
- `scripts/pause_indicator_lite.lua`
- `script-opts/pause_indicator_lite.conf`
- `script-opts/modernz.conf` (→ `margo-osc.conf` olarak taşınır)

### Bileşen 1: İnce alt çubuk

modernz'in yerleşik `persistentprogress=yes`'i ile sağlanır. `persistentprogressheight`
(varsayılan 17) progressbar'ın ~3px inceliğine yaklaşacak şekilde ayarlanır.

**Risk / yedek plan:** modernz'in `persistentprogress` görünümü, kullanıcının sevdiği
progressbar çubuğuna görsel olarak yeterince benzemezse, progressbar'ın *sadece* ince-çubuk
renderer'ı (`render_persistentprogressbar` + ilgili state) margo-osc.lua'ya bağımsız blok
olarak taşınır (Yaklaşım 3), gerisi yine atılır. Bu karar uygulama sırasında **görsel
doğrulama** ile verilir.

### Bileşen 2: Merkez pause glyph

`pause_indicator_lite.lua`'nın çizim mantığı (pause çubukları/dikdörtgenler, opsiyonel
flash play üçgeni, opsiyonel mute ikonu — 3 overlay) margo-osc.lua'ya kendi içinde kapalı
bir blok olarak taşınır. Config seçenekleri (`pause_indicator_lite.conf`'tan) margo-osc.conf'a
bir bölüm olarak eklenir; ad çakışmasını önlemek için gerekirse önek verilir. `keybind_allow`
varsayılanı `no`.

### Script kimliği ve referans güncellemeleri

mpv script adı dosya adından türer: `margo-osc.lua` → iç ad `margo_osc`. Bu yüzden
`modernz`'e yapılan tüm iç atıflar güncellenmeli:

- `input.conf:108`: `DEL script-binding modernz/visibility` → `... margo_osc/visibility`
- `margo-osc.conf` (~9 satır): `script-message-to modernz osc-hide` → `... margo_osc osc-hide`
  (title/playlist/volume/track/chapter mouse-komutları).
- Kayıtlı mesaj/binding **adları** değişmez (`osc-visibility`, `osc-hide`, `visibility`,
  `progress-toggle`, `thumbfast-info` vb.); yalnızca script-adı öneki değişir.
- `mpv.conf`'taki `osc=no` aynı kalır.

## Kapsam dışı (YAGNI)

- Sistem saati (progressbar özelliği) — istenmedi.
- `.`/`,` frame-step tuşları — mpv'de yerleşik, progressbar'ınki tekrardı.
- progressbar'ın hover-genişleyen alt çubuğu, kendi seekbar/chapter/süre/başlık çizimi —
  hepsi modernz'de var, atılıyor.

## Doğrulama planı

İzole config kopyasında (canlı config'e dokunmadan), `--config-dir` ile:
1. margo-osc yükleniyor, Lua hatası yok.
2. Oynatırken en altta ince sürekli çubuk görünüyor (mevcut progressbar görünümüyle karşılaştır).
3. Fareyi alt kenara götürünce tam OSC açılıyor (seekbar, süreler, butonlar).
4. Duraklatınca ekran ortasında **tek** pause glyph (çift değil).
5. `DEL` OSC görünürlüğünü toggle ediyor (`margo_osc/visibility` dispatch).
6. Çift seekbar yok, çift merkez-pause yok.
7. mpv'nin `input-bindings`'inde `margo_osc/*` bağlamaları doğru.

## Uygulama notları

- modernz.lua büyük (3792 satır) ve ayarlı; gövdesi **olabildiğince değiştirilmeden**
  taşınır (yalnızca merkez-pause bloğu eklenir). Bu, davranış denkliğini korur ve riski azaltır.
- Yedek: değişiklik öncesi tüm mpv script/conf'ları yedeklenir.
- Grafik güncellenir (`graphify update .`).
