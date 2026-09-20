# voca — Vocalinux (yerel sesle yazma) modülü

[Vocalinux](https://github.com/VocaHQ/vocalinux): bas-konuş (push-to-talk) ile her uygulamaya
yerel/offline sesle yazma. Motor: **whisper.cpp** (`python-pywhispercpp`).

Bu modül, AUR'un hazır `python-pywhispercpp-cpu` paketinin bu makinede yol açtığı
**"bazen çalışıyor, bazen çalışmıyor"** sorununu kalıcı olarak çözer: `pywhispercpp`'yi
**AVX2 + Vulkan** ile kendi PKGBUILD'imizden derler ve vocalinux'u buna bağlar.

## İçindekiler

```
modules/voca/
├── module.yaml                      # mdots modülü: pre-install hook + ~/.local/bin bağları
├── packages.yaml                    # vocalinux + Vulkan/VAD/Wayland bağımlılıkları
├── config/                          # vocalinux config yedekleri = model profilleri
│   ├── vocalinux.small.json         #   hızlı  (ggml-small.bin, ~2 sn)
│   ├── vocalinux.turbo.json         #   doğru  (ggml-large-v3-turbo-q5_0, ~8 sn)
│   └── vocalinux.large.json         #   ORİJİNAL (ggml-large-v3.bin) — düzeltmeden önceki hali
├── pkgbuild/python-pywhispercpp-vulkan/PKGBUILD   # Vulkan + native-CPU derleme tarifi
├── scripts/
│   ├── install.sh                   # pre-install hook (idempotent; gerekirse derler)
│   ├── post-install.sh              # post-install hook (voca-doctor özeti; sync'i bozmaz)
│   ├── build-pywhispercpp.sh        # → ~/.local/bin/voca-build  (derle + doğrula + kur)
│   ├── voca-doctor.sh               # → ~/.local/bin/voca-doctor (sağlık kontrolü + benchmark)
│   ├── voca-model.sh                # → ~/.local/bin/voca-model  (model profilini değiştir/yedekle)
│   └── lib.sh                       # ortak yardımcılar
└── README.md
```

## Sorun neydi? (kök nedenler)

Belirtiler: kayıt bırakınca metin çok geç geliyor / hiç gelmiyor, `vocalinux` boşta bile
%450-650 CPU yiyor, bazen `vk::Queue::submit: ErrorDeviceLost`.

| # | Kök neden | Kanıt | Çözüm |
|---|-----------|-------|-------|
| 1 | AUR `python-pywhispercpp-cpu` **AVX2/FMA'sız (jenerik SSE2)** derleniyor. ggml, `SOURCE_DATE_EPOCH` tanımlıysa `GGML_NATIVE`'i otomatik kapatır; `makepkg` bunu **her zaman** tanımlar, yani `makepkg.conf`'taki `-march=native` fiilen etkisiz kalır. | `objdump -d libggml-cpu.so \| grep -c ymm` → **0** (CPU `avx2 fma avx_vnni` destekliyor). `base` modeli 0.8 sn'lik kaydı **27 sn**'de çözdü. | `-DGGML_NATIVE=ON` (PKGBUILD) → ymm=11 825, vfmadd=506 |
| 2 | `-cpu` paketinde **Vulkan yok**; Intel Arc iGPU hiç kullanılmıyor. | `system_info`'da yalnızca `OPENMP \| REPACK` | `-DGGML_VULKAN=ON` → `libggml-vulkan.so`; vocalinux backend'i *Vulkan → CUDA → CPU* sırasıyla otomatik seçer |
| 3 | `large-v3` (1.55 milyar parametre) bu donanım için fazla ağır: whisper, kayıt kaç sn olursa olsun **her zaman 30 sn'lik pencereyi** encode eder. CPU'da 45 sn, iGPU'da 12-15 sn sürer ve `xe` sürücüsünün **GPU watchdog'una** takılır. | `journalctl -k`: `xe … GT0: Timedout job … in python` → uygulamada `ErrorDeviceLost` | Daha hafif model: `large-v3-turbo-q5_0` (aşağıdaki tablo) |
| 4 | `python-onnxruntime` yok → **Silero neural VAD** devre dışı, kaba genlik VAD'ine düşüyor. Sessizlikte "Altyazı M.K." gibi halüsinasyonlar ve gereksiz uzun segmentler. | vocalinux logu: `Silero VAD unavailable … No module named 'onnxruntime'` | `python-onnxruntime-cpu` (packages.yaml) |

## Kurulum

### Otomatik (önerilen): mdots

`hosts/hay.yaml` → `enabled_modules` listesine `voca` eklenir (bu repoda ekli), sonra:

```bash
mdots sync
```

Akış (sıra önemli):

1. **pre-install hook** (`scripts/install.sh`): pywhispercpp zaten AVX2+Vulkan'lıysa saniyeler
   içinde çıkar. Değilse `voca-build`'i çalıştırır (~4-8 dk).
   *Neden paketlerden önce?* `vocalinux` (AUR) `python-pywhispercpp` ister; AUR yardımcısı bunu
   AVX2'siz `-cpu` paketiyle karşılayabilir. Önce bizim paketimiz (`provides=python-pywhispercpp`)
   kurulu olunca bağımlılık onunla sağlanır.
2. `packages.yaml`: `vocalinux`, Vulkan çalışma zamanı, `python-onnxruntime-cpu`, `wtype` vb.
3. `dotfiles`: `voca-build`, `voca-doctor` ve `voca-model` → `~/.local/bin`.
4. **post-install hook** (`scripts/post-install.sh`): `voca-doctor`'ı çalıştırıp yalnızca sorun/uyarı
   satırlarını ve özeti basar. Bilgilendiricidir, sync'i asla başarısız etmez. (mdots, `scripts/`
   dizini olan modülde `post_install_hook` yoksa uyarı verir; bu hook aynı zamanda onu karşılar.)

> **Hook'lar kullanıcı olarak çalışır** (`module.yaml` → `run_hooks_as_user: true`). mdots'un
> varsayılanı `sudo bash hook` yani **root**'tur: `makepkg` root'ta çalışmaz, `voca-doctor` da root'un
> `HOME`'una/gruplarına bakıp sahte alarm verirdi (`input grubunda değilsin`, `config yok`…).
> `sudo -u` ortamı sıfırladığı için doctor oturum tipini `loginctl`'den de okuyabilir.

### Elle

```bash
voca-build            # sağlıksızsa derle + doğrula + kur; sağlıklıysa hiçbir şey yapmaz
voca-build --force    # yine de yeniden derle
voca-build --no-install   # sadece derle (~/.cache/voca-build altında kalır)
```

`voca-build` şunları yapar: PKGBUILD'i `~/.cache/voca-build`'e kopyalar → `makepkg -sf` →
**kurmadan önce paketi doğrular** (AVX2 komutu var mı, `libggml-vulkan.so` var mı; yoksa kurmaz)
→ `sudo pacman -U --ask 4` (mevcut `python-pywhispercpp-*` paketinin yerini alır).

> Kurduktan sonra **vocalinux'u yeniden başlat**: çalışan süreç eski kütüphaneleri bellekte tutar.

## Doğrulama

```bash
voca-doctor
```

Kontroller: oturum/`wtype`/`input` grubu, pywhispercpp sağlayıcısı ve **AVX2/FMA sayısı**,
Vulkan cihazı, `onnxruntime`, seçili model + dosya, **xe watchdog** olayları, vocalinux'un
**boştaki CPU'su** ve **çalışan sürecin yüklediği modelin config'le uyuşup uyuşmadığı** (vocalinux config'i
yalnızca başlarken okur; süreç çalışırken config'i değiştirmek sessizce boşa gider → `✗ … yeniden başlat`).
Sağlıklı sistemde beklenen: `sorun yok`.

Vocalinux logunda da şunları görmelisin (tray → Logs veya terminalden `vocalinux`):

```
Using Silero neural VAD
Using Vulkan GPU [0]: Intel(R) Arc(tm) Graphics (MTL)
whisper.cpp model file: …/ggml-small.bin (465.0 MB)      # ya da ggml-large-v3-turbo-q5_0.bin (turbo profili)
```

## Model seçimi

Ölçüm: Core Ultra 7 155H + Intel Arc iGPU (Meteor Lake, Mesa/Xe KMD), 0.8 sn'lik kayıt,
kararlı durum. Süre büyük ölçüde kayıt uzunluğundan **bağımsız** (sabit 30 sn'lik encoder penceresi).

| Model | Vulkan (iGPU) | CPU (AVX2) | Not |
|-------|--------------:|-----------:|-----|
| `base` | **0.3 sn** | 2.6-3.2 sn | Hızlı ama Türkçede zayıf |
| `small` | **1.3 sn** | ~10 sn | Hızlı diktasyon; orta doğruluk (**`small`** profili) |
| `medium-q5_0` | ~5 sn | 19-23 sn | `turbo-q5_0`'dan hem yavaş hem daha az doğru |
| **`large-v3-turbo-q5_0`** | **~6.4 sn** | — | `large` kalitesine yakın, kararlı (**`turbo`** profili) |
| `large-v3` (f16) | 12-15 sn + **ErrorDeviceLost** | 45 sn | Bu donanımda önerilmez (watchdog) |
| *(referans)* `base`, SIMD'siz eski derleme | — | **27 sn** | Düzeltmeden önce |

Hız öncelikliyse `small`; doğruluk öncelikliyse `large-v3-turbo-q5_0`.

**Gerçek konuşmayla ölçüm** (7.5 sn'lik Türkçe cümle, `voca-doctor --bench`, Vulkan, 3 ardışık çalıştırma):

| Model | Süreler (sn) | Sonuç |
|-------|--------------|-------|
| `small` | 1.8 · 2.0 · 3.6 | **~2 sn — turbo'dan ~4× hızlı** |
| `large-v3-turbo-q5_0` | 9.7 · 8.2 · 7.1 | ~8 sn |

Konuşma varken decoder de çalıştığı için süreler kısa-kayıt ölçümünden biraz yüksek; oran aynı kalıyor.
Test cümlesi espeak-ng (robot ses) olduğu için **doğruluk karşılaştırması için güvenilir değil**
(ikisi de hatalı çıktı); gerçek diktasyonda `small` Türkçede ve İngilizce kelimelerde belirgin hata
yapıyor ("yedeği" → "yediği", "backup" → "bake kapı"). Hız/doğruluk takası senin kararın.

### Profiller — `voca-model`

`config/vocalinux.<profil>.json` dosyaları, o modelle çalışan vocalinux config'inin **tam yedeğidir**:
`small` (hızlı), `turbo` (doğru) ve `large` (vocalinux'un düzeltmeden önceki **orijinal** hali).
`voca-model` bunlar arasında tek komutla geçer (`voca-doctor --model …` aynı işi yapar):

```bash
voca-model              # mevcut model + profil listesi (* = aktif)   [voca-doctor --model]
voca-model small        # hızlı profil                                [voca-doctor --model small]
voca-model turbo        # doğru profil
voca-model large        # orijinal profil (önerilmez: iGPU watchdog'u)
voca-model save         # canlı config'i, mevcut modele uyan profil yedeğine yaz
voca-model save small   # ya da adını ver (yeni profil için: kendi adın)
```

`voca-model <profil>`: model dosyasının var olduğunu kontrol eder → vocalinux'u durdurur (çıkışta
config'i geri yazdığı için) → **yalnızca 3 model anahtarını** (`model_size`,
`whisper_cpp_model_size`, `whisper_cpp_model_variant`) canlı config'e işler; kısayol, ses aygıtı vb.
ayarların olduğu gibi kalır → önceki config'i `config.json.bak-voca-model`'e yedekler → vocalinux'u
yeniden başlatır ve **logdan gerçekten hangi modelin yüklendiğini yazar** (`yüklendi: …ggml-….bin`).

Vocalinux boot'ta **systemd birimi** olarak çalışıyorsa (aşağıya bak) `voca-model` süreci `kill`
etmek yerine `systemctl --user stop/start app-vocalinux@autostart.service` kullanır; elle
başlatılmışsa süreci durdurup yeniden başlatır (çıktısı `~/.local/state/voca/vocalinux.log`).

Yeni profil: vocalinux'ta modeli değiştirip ayarla, sonra `voca-model save <ad>`. Profillerde gizli
bilgi yoktur (`remote_api_key` boş); uzak API anahtarı girersen o profili repoya alma.

**Elle değiştirmek:** vocalinux Settings → Model, ya da `~/.config/vocalinux/config.json`
(vocalinux çalışmıyorken düzenle — çıkışta config'i geri yazar):

```json
"whisper_cpp_model_size": "large-v3-turbo-q5_0",
"whisper_cpp_model_variant": "large-v3-turbo-q5_0"
```

Model dosyaları `~/.local/share/vocalinux/models/whispercpp/ggml-<ad>.bin`
(uygulama kendisi indirir; elle: `https://huggingface.co/ggerganov/whisper.cpp`).

**Kendin ölç:** `voca-doctor --bench small large-v3-turbo-q5_0` — her modeli Vulkan ve CPU'da 3'er kez
süreler ve transkripti gösterir. Test kaydı: `espeak-ng` varsa Türkçe konuşma (decoder dahil), yoksa 1 sn
sessizlik (yalnızca encoder). Kendi kaydınla: `--bench --clip kayit.wav MODEL…`; yalnızca Vulkan:
`VOCA_BENCH_BACKENDS=vulkan voca-doctor --bench …` (CPU'da büyük modeller dakikalar sürer).

## Boot'ta otomatik başlama

Vocalinux ilk çalışmada kendi XDG autostart girdisini oluşturur (`~/.config/autostart/vocalinux.desktop`,
`Exec=/usr/bin/vocalinux --start-minimized`). Bu oturumda uygulamaları margo'nun kendi autostart'ı
(`margo-autostart-*.scope`) başlatır, ama XDG girdilerini **systemd** işler:
`systemd-xdg-autostart-generator` girdiden `app-vocalinux@autostart.service` üretir.

```bash
systemctl --user status app-vocalinux@autostart.service      # durum
journalctl --user -u app-vocalinux@autostart.service -f      # log
systemctl --user restart app-vocalinux@autostart.service     # yeniden başlat
```

> **Tuzak (düzeltildi):** süreç `python /usr/bin/vocalinux --start-minimized` komut satırıyla çalışır.
> Sonu `$` ile sabitlenmiş bir `pgrep -f '/usr/bin/vocalinux$'` bunu **kaçırır** ve script'ler
> "çalışmıyor" sanıp config'e dokunurdu (vocalinux çıkışta config'i geri yazdığı için değişiklik
> sessizce kaybolurdu). `scripts/lib.sh` → `voca_pid()` artık süreç adına (`pgrep -x vocalinux`) bakar.

## Bakım

- **Python'un minör sürümü yükselince** (ör. 3.14 → 3.15) `_pywhispercpp.cpython-314-….so` ABI'si
  uymaz → `voca-build --force`.
- **vocalinux güncellenince** ekstra bir şey gerekmez (`python-pywhispercpp` bağımlılığı bizim
  paketle sağlanır). Yeni bir vocalinux pywhispercpp ≥ 1.5 isterse PKGBUILD'deki `commit=` pin'ini
  güncelle ve `voca-build --force` çalıştır.
- **PKGBUILD `-march=native` kullanır**: derleme bu CPU'ya özeldir, başka makineye taşıma; orada yeniden derle.
- İlk açılışta vocalinux kendi autostart girdisini oluşturur (`~/.config/autostart/vocalinux.desktop`,
  `general.first_run`). İstemiyorsan o dosyayı sil ve config'te `"autostart": false` yap.

## Sorun giderme

| Belirti | Sebep / çözüm |
|---------|----------------|
| `vk::Queue::submit: ErrorDeviceLost`, `journalctl -k` → `Timedout job` | iGPU watchdog'u; model çok ağır. `large-v3-turbo-q5_0` veya `small` kullan. |
| Boşta %100+ CPU | Takılmış transkripsiyon ya da SIMD'siz derleme. `voca-doctor`; `voca-build --force`; vocalinux'u yeniden başlat. |
| Sessizlikte "Altyazı M.K." / uydurma cümle | Neural VAD kapalı → `python-onnxruntime-cpu` kurulu mu? Logda `Using Silero neural VAD` görünmeli. |
| `voca-model` "çalışmıyordu" diyor ama vocalinux çalışıyor | Eski sürüm süreci `--start-minimized` argümanı yüzünden bulamıyordu; düzeltildi (`voca_pid`). Güncel `voca-doctor` süreci ve yüklü modeli gösterir. |
| Kısayol hiç tepki vermiyor | `input` grubu: `sudo usermod -aG input $USER` + yeniden giriş. Kısayol config'te `right_alt+right_alt` (push-to-talk). |
| Metin yazılmıyor (Wayland) | `wtype` kurulu mu (`voca-doctor`)? Compositor `virtual-keyboard` protokolünü desteklemeli (margo destekliyor). |
| `vulkaninfo found no devices` uyarısı | `vulkan-tools` + `vulkan-intel` kurulu olmalı. |
| Derleme hatası | `~/.cache/voca-build/build.log`; makedepends'i `makepkg -s` kurar (sudo ister). |

## Geri alma

- Paket: `sudo pacman -U --ask 4 <eski .pkg.tar.zst>` (bu makinede yedek: `~/.cache/pywhispercpp-backup/`)
  ya da snapper snapshot'ı (paket kurulumları `pre/post` snapshot alır).
- Config: `voca-model large` (orijinal, düzeltme öncesi `large` model + o günkü tüm ayarlar),
  `~/.config/vocalinux/config.json.bak-voca-model` (her `voca-model` geçişinden önceki hali) ya da
  `config/` altındaki diğer profiller. Not: `large`'a dönmek 12-45 sn gecikme ve GPU watchdog riski demektir.
- Modülü devre dışı bırakmak: `hosts/hay.yaml`'dan `voca` satırını sil (kurulu paketlere dokunmaz).
