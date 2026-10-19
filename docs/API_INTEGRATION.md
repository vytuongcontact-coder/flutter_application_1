# Tích hợp Student App API

Nguồn hợp đồng: `Student App API.pdf` người dùng cung cấp. Base URL mặc định:
`https://api.ngoisaoviet.info`. Không cần sửa URL để chạy máy ảo Android.

## 1. Chạy và đăng nhập

```sh
flutter pub get
flutter run -d emulator-5554
```

Sau splash, chọn **Tài khoản** → nhập MSSV và mật khẩu → **ĐĂNG NHẬP**.
Trang chủ vẫn xem được khi chưa đăng nhập. Chọn **Điểm danh** lúc chưa có phiên sẽ
mở đăng nhập và quay lại Điểm danh khi đăng nhập thành công.

Không có tài khoản hay mật khẩu thật trong mã nguồn, test hoặc cấu hình build.
Nếu đổi môi trường, dùng URL HTTPS của máy chủ được phép:

```sh
flutter run --dart-define=UEH_API_URL=https://your-api.example
```

## 2. Đăng nhập và quản lý phiên

`lib/services/student_api.dart` gửi `POST /api/login` với `mssv`, `mat_khau`.
Cặp `token`, `refresh_token` lưu cùng một bản ghi qua `SecureTokenStore`;
mật khẩu không được lưu. App đọc lại phiên khi khởi động.

Các request có xác thực gửi `Authorization: Bearer ...`. Khi gặp 401:

1. Bỏ cặp token cũ khỏi bộ nhớ lưu bền trước khi dùng refresh token, tránh replay nếu app bị đóng đột ngột. Gửi `POST /api/refresh-token` một lần; các request đồng thời chờ cùng một Future.
2. Lưu ngay cặp token mới rồi gọi lại request ban đầu đúng một lần.
3. Nếu refresh thất bại hoặc retry vẫn 401, xóa phiên và yêu cầu đăng nhập lại.

Refresh token chỉ dùng một lần. Nếu refresh timeout/mất mạng hoặc không lưu được
cặp mới, app yêu cầu đăng nhập lại để tránh gửi lại token có thể đã bị server thu hồi.
Mất mạng khi lấy hồ sơ thông thường vẫn giữ phiên và cho phép thử lại.

Nút đăng xuất xóa token khỏi thiết bị và bỏ thông tin sinh viên trên UI. PDF không
có API logout/revoke, nên thao tác này không thu hồi token ở server.

## 3. Thẻ sinh viên

Sau đăng nhập, app gọi `GET /api/student-info`. `StudentProfile.fromJson` ánh xạ
đúng các trường trong PDF, đổi ngày sang `dd/MM/yyyy`, đổi `gioiTinh` thành Nam/Nữ.
Ảnh tải từ URL HTTPS, có biểu tượng thay thế nếu ảnh lỗi. QR chứa MSSV trả về từ API.
Không sử dụng thông tin/ảnh của thẻ sinh viên mẫu làm dữ liệu tài khoản.

## 4. Điểm danh

- Nhập mã gồm 6 chữ/số hoặc quét QR/Barcode để điền mã. Quét xong cần nhấn **Điểm danh**.
- Gửi `POST /api/attendance` với `code` đã chuẩn hóa.
- PDF không có endpoint xem cấu hình đợt. App gửi mã trước; chỉ khi nhận lỗi 400
  yêu cầu `latitude, longitude` mới xin quyền vị trí và lấy GPS hiện tại để gửi lại.
- Không có ô nhập tọa độ và không hardcode tọa độ cơ sở B vào request.
- Các lỗi sai mã, trùng điểm danh, ngoài giờ, ngoài phạm vi hiển thị thông báo từ server.
- Kết quả thành công hiển thị tên đợt, thời gian server theo giờ Việt Nam và khoảng cách nếu có.
- Không tự động gửi lại điểm danh khi timeout; người dùng chủ động thử lại và server
  sẽ trả 409 nếu lần trước đã được ghi nhận.

Android đã khai báo Internet, camera và vị trí khi sử dụng. iOS/macOS đã khai báo
chuỗi giải thích quyền; iOS có Keychain entitlement. Chưa build/kiểm thử iOS/macOS.
Khi chuẩn bị phát hành iOS, kiểm tra cấu hình quyền foreground của geolocator trong
Xcode/Pods/SPM theo phiên bản plugin được resolve.

## 5. Các tính năng cần thêm API

Màn hình đăng nhập có nút Email UEH, Email khách và Sign in with Apple theo mẫu.
Ba nút này hiện thông báo chưa hỗ trợ khi nhấn; hiện chỉ MSSV/mật khẩu gọi API đăng nhập.
Xác thực khuôn mặt hiện ở trạng thái chưa hỗ trợ. Thông báo,
xem điểm, thời khóa biểu, lịch thi và lịch sử điểm danh chưa có endpoint trong PDF.
Không tạo endpoint hoặc dữ liệu thành công giả cho các chức năng này.

## 6. Kiểm thử

```sh
flutter analyze
flutter test
```

- `test/student_api_test.dart`: request/response, dữ liệu hồ sơ, lưu/khôi phục/xóa phiên,
  refresh đồng thời, giới hạn retry, đăng xuất trong lúc refresh, lỗi mạng/JSON/nghiệp vụ.
- `test/auth_flow_test.dart`: bảo vệ Điểm danh, validation, hiện/ẩn mật khẩu,
  khóa nút khi đang gửi, đăng nhập/đăng xuất, giao diện nhỏ, GPS khi cần và từ chối quyền.
- Các test cũ vẫn kiểm tra splash, drawer và tin tức.

Kiểm tra thủ công: đăng nhập → xem thẻ → khởi động lại app → kiểm tra phiên → đăng xuất.
Để xác nhận điểm danh thực tế cần mã đợt đang mở do admin cấp; nếu yêu cầu vị trí,
thiết bị phải đang ở trong phạm vi cho phép. Không dùng tọa độ giả để xác nhận điểm danh.

Kết quả kiểm tra ngày 01/10/2026:

- `flutter analyze`: không có lỗi/cảnh báo.
- `flutter test`: 22 test đạt; 1 test tin tức live có sẵn được bỏ qua mặc định.
- API thật: login 200, student-info 200 đúng MSSV, refresh 200 đổi refresh token,
  student-info sau refresh tiếp tục 200. Không lưu response chứa token vào dự án.
- Build và chạy trên Android emulator API 37: đăng nhập, hiển thị thẻ, giữ phiên sau
  khi đóng/mở tiến trình và đăng xuất đã kiểm tra bằng thao tác UI.
- Điểm danh thật không vị trí: thao tác nhập mã trong app đã thành công cho đợt
  “Điểm danh lớp Mobile 2 (CT2)”; giờ server `2026-10-01 15:54:16` (UTC+7).
  Ảnh kết quả: [attendance-no-location.png](attendance-no-location.png).
- Điểm danh có vị trí: đã có mã do người dùng cấp; chưa gửi yêu cầu kiểm thử vì
  cơ chế duyệt tự động yêu cầu xác nhận rõ việc gửi tọa độ máy ảo tới API.
  Camera/GPS còn cần xác nhận thực tế sau khi bước này được cho phép.

Tài liệu thư viện chính thức:
[secure storage](https://pub.dev/packages/flutter_secure_storage),
[geolocator](https://pub.dev/packages/geolocator),
[mobile scanner](https://pub.dev/packages/mobile_scanner).
