# UEH Student

Ứng dụng Flutter hiển thị tin tức UEH tại `https://ueh.edu.vn/tintucmobile`, có splash, Drawer và thanh điều hướng dưới.

## Chức năng hiện có

- Splash UEH hiển thị 2 giây trước khi vào trang chủ.
- WebView có tiến trình tải, tải lại, thông báo lỗi và thử lại.
- AppBar nền xanh UEH, tiêu đề theo trang đang hiển thị.
- Drawer có logo, icon Font Awesome và 11 mục; Thời khóa biểu và Lịch thi là hai mục riêng.
- Thanh điều hướng dưới gồm Trang chủ, Thông báo, Điểm danh, Tài khoản.

Trang chủ và Tin tức UEH đã mở được website. Các mục khác đang chờ liên kết hoặc triển khai màn hình; khi chọn sẽ hiển thị thông báo chưa khả dụng.

## Cấu trúc mã nguồn

- `lib/main.dart`: theme và `MaterialApp.router`.
- `lib/routers/app_router.dart`: `/` (splash) và `/home` (WebView).
- `lib/widgets/splash_screen.dart`: hiển thị ảnh 2 giây, dùng `BoxFit.cover` để cắt phần thừa quanh tâm mà không bóp méo ảnh; dùng `go('/home')` để không quay lại splash.
- `lib/widgets/home_screen.dart`: WebView UEH, tiến trình tải, báo lỗi/thử lại và xử lý menu.
- `lib/widgets/app_top_bar.dart`: AppBar dùng chung, nhận tên trang.
- `lib/widgets/app_drawer.dart`: logo và danh sách menu bên trái.
- `lib/widgets/app_bottom_bar.dart`: thanh điều hướng dưới với 4 mục.
- `flutter_native_splash.yaml`: cấu hình splash native, hỗ trợ cả giao diện sáng và tối.

Ảnh có sẵn thực tế là `assets/images/nso-splash-landscape-1499x999.png`. Giữ nguyên tên và đường dẫn này.

## Chạy ứng dụng

Yêu cầu Flutter có Dart đáp ứng `^3.13.2` theo `pubspec.yaml`. Môi trường đã kiểm tra: Flutter 3.47.2 / Dart 3.13.2. Cài Android SDK để chạy Android; iOS/macOS cần macOS và Xcode.

```sh
flutter pub get
dart run flutter_native_splash:create
flutter run
```

Màn hình WebView hỗ trợ Android, iOS và macOS. Trên Web/Windows/Linux ứng dụng hiển thị thông báo nền tảng chưa hỗ trợ thay vì khởi tạo WebView. Android đã có quyền INTERNET; macOS đã có quyền network.client cho debug và release. URL HTTPS mặc định không cần mở ngoại lệ bảo mật HTTP trên iOS.

Đổi `HomeScreen.websiteUrl` hoặc truyền URL khi chạy:

```sh
flutter run --dart-define=UEH_URL=https://ueh.edu.vn/tintucmobile
```

Đổi thời lượng splash bằng `SplashScreen.displayDuration`. Sau khi thay ảnh/cấu hình native, chạy lại lệnh tạo splash và khởi động lại ứng dụng hoàn toàn; hot reload không cập nhật splash native.

## Giới hạn splash native

`flutter_native_splash` tạo tài nguyên khởi động trước khi Flutter vẽ giao diện. Android 11 trở xuống kéo ảnh nền theo cửa sổ; iOS dùng `scaleAspectFill`. Android 12 trở lên chỉ cho phép nền màu và ảnh ở giữa bị mask, không hỗ trợ ảnh nền tràn màn hình. Vì vậy splash Flutter ngay sau đó dùng ảnh gốc với `BoxFit.cover` để bảo đảm có màn hình ảnh UEH tràn khung, cắt theo tỷ lệ thiết bị. macOS hiển thị splash Flutter, không có splash native từ package này.

Tài liệu: https://pub.dev/packages/flutter_native_splash

## Kiểm tra

```sh
flutter analyze
flutter test
```

Widget test kiểm tra chuyển từ splash sang màn hình chính, không giữ splash trong lịch sử, và hủy timer khi widget bị đóng. Cần chạy trên thiết bị Android/iOS/macOS để kiểm tra tải website và splash native thực tế.

## Commit và publish bằng GitHub Desktop

1. Chọn **File → Add Local Repository…**, trỏ đến thư mục dự án `flutter_application_1` chứa file README này.
2. Trong **Changes**, xem các file mã nguồn, cấu hình nền tảng và ảnh sẽ được commit.
3. Nhập Summary, ví dụ: `Initial commit: UEH Student Flutter app`, rồi chọn **Commit to main**.
4. Chọn **Publish repository**, đặt tên repository trên GitHub và chọn chế độ public/private theo nhu cầu, sau đó xác nhận publish.
5. Các lần sau: xem Changes → nhập Summary → Commit → **Push origin**.

Giữ `pubspec.lock`, `.metadata`, mã nguồn các nền tảng và tài nguyên splash native trong repository. `.gitignore` loại bỏ cache, build, thiết lập SDK cục bộ và thông tin ký ứng dụng. `.gitattributes` thống nhất cách lưu xuống dòng và xử lý ảnh dưới dạng binary.

Hướng dẫn chính thức: [thêm repository vào GitHub Desktop](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-a-repository-from-your-local-computer-to-github-desktop), [publish dự án lên GitHub](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-an-existing-project-to-github-using-github-desktop).
