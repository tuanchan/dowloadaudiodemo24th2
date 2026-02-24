# 📱 YT Downloader — Flutter App

Ứng dụng tải audio/video từ YouTube. Build tự động qua GitHub Actions. Ký và cài đặt qua **Sideloadly** hoặc **eSign** (không cần jailbreak, không cần App Store).

---

## 🏗️ Kiến trúc

```
lib/
├── main.dart                    # Entry point, theme
├── models/
│   └── download_model.dart      # VideoInfo, DownloadTask, streams
├── services/
│   └── download_service.dart    # Core logic: fetch info + download
├── screens/
│   └── home_screen.dart         # Main UI (2 tabs)
└── widgets/
    ├── video_info_card.dart      # Hiển thị thumbnail + info
    ├── stream_selector_sheet.dart # Chọn chất lượng
    ├── download_progress_card.dart # Thanh tiến trình
    └── download_history_tab.dart # Lịch sử tải
```

### Thư viện chính
| Package | Mục đích |
|---------|----------|
| `youtube_explode_dart` | Extract stream URLs từ YouTube (pure Dart, chạy trên iOS) |
| `dio` | Download file với progress callback |
| `path_provider` | Lấy thư mục lưu file |
| `open_file` | Mở file sau khi tải |
| `share_plus` | Chia sẻ file |

> **Lưu ý**: App dùng `youtube_explode_dart` thay vì binary `yt-dlp` vì iOS không cho chạy binary bên ngoài. Thư viện này có chức năng tương đương, pure Dart, không cần server.

---

## 🚀 Setup & Build

### Yêu cầu
- Flutter 3.19+ (`flutter --version`)
- Xcode 15+ (chỉ cần build iOS)
- CocoaPods (`sudo gem install cocoapods`)

### Build local
```bash
# Clone project
git clone https://github.com/YOUR_USERNAME/ytdlp_downloader
cd ytdlp_downloader

# Cài dependencies
flutter pub get
cd ios && pod install && cd ..

# Chạy trên simulator
flutter run

# Build IPA (unsigned)
flutter build ios --release --no-codesign
cd build/ios/iphoneos
mkdir -p Payload && cp -r *.app Payload/
zip -r ../../../YTDownloader.ipa Payload/
```

---

## ⚙️ GitHub Actions — Build tự động

Workflow tại `.github/workflows/ios_build.yml` tự động:
1. Build Flutter iOS release (no code sign)
2. Đóng gói thành file `.ipa`
3. Upload artifact lên GitHub Actions
4. Tạo Release khi push tag `v*`

### Cách dùng:

**Build thủ công:**
```
GitHub repo → Actions → "Build iOS IPA" → Run workflow
```

**Build khi push tag:**
```bash
git tag v1.0.0
git push origin v1.0.0
# → Tự động build + tạo Release với file IPA đính kèm
```

**Tải IPA:**
```
Actions → chọn workflow run → Artifacts → YTDownloader-iOS-xxx
```

---

## ✍️ Ký App & Cài đặt (Sideload)

### Phương pháp 1: Sideloadly (PC/Mac — Khuyến nghị)

**Ưu điểm:** Dễ dùng, miễn phí, không cần jailbreak

1. **Tải Sideloadly**: https://sideloadly.io/
2. Kết nối iPhone/iPad qua **USB**
3. Mở Sideloadly, kéo thả file `YTDownloader.ipa`
4. Nhập **Apple ID** (nên dùng tài khoản phụ)
5. Nhập **mật khẩu** (Sideloadly không lưu)
6. Nhấn **Start** — chờ 1-2 phút

**Sau khi cài:**
- Vào `Settings → General → VPN & Device Management`
- Tìm tên Apple ID của bạn → nhấn **Trust**
- Mở app

> ⚠️ Free Apple ID: app hết hạn sau **7 ngày** (cần re-sign)  
> 💰 Developer Account ($99/năm): hết hạn sau **1 năm**

---

### Phương pháp 2: eSign (Trực tiếp trên iPhone — Không cần PC)

**eSign** là app manager cho phép ký và cài IPA trực tiếp trên thiết bị.

**Cài eSign:**
1. Mở Safari, truy cập: `https://esign.yyyue.xyz`
2. Cài profile từ trang web (trust trong Settings)
3. Mở eSign app

**Import certificate:**
```
eSign → Settings → Certificate → Import
```
Dùng certificate `.p12` + `.mobileprovision` (mua từ các dịch vụ như:
- SignTools 4, AppDb, Scarlet v2, ReProvision)

**Cài IPA:**
1. Trong eSign: `Apps → Import IPA`
2. Chọn file `YTDownloader.ipa` (từ Files app)
3. Chọn certificate → Sign
4. Install → Trust trong Settings

---

### Phương pháp 3: AltStore (Miễn phí, Ổn định)

1. Tải **AltServer** về PC/Mac: https://altstore.io/
2. Cài AltStore lên iPhone qua AltServer
3. Trong AltStore: **My Apps → +** → chọn IPA
4. Mỗi 7 ngày refresh qua AltServer (hoặc auto nếu trên cùng WiFi)

---

## 📁 File được lưu ở đâu?

**iOS:**
- `Files app → On My iPhone → YT Downloader → Downloads/`
- Có thể chia sẻ qua AirDrop, iCloud, v.v.

**Android:**
- `/storage/emulated/0/Download/YTDownloader/`

---

## 🛠️ Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| "URL không hợp lệ" | Kiểm tra URL youtube.com hoặc youtu.be |
| "Video không tồn tại" | Video bị xóa hoặc private |
| Build thất bại | Kiểm tra Flutter version, pod install |
| App bị trust error | Settings → VPN & Device Management → Trust |
| App hết hạn 7 ngày | Re-sign qua Sideloadly/AltStore |
| Network error | Kiểm tra WiFi, VPN nếu cần |

---

## 📄 License
MIT License — Chỉ dùng cho mục đích cá nhân.
