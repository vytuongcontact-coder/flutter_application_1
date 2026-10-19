import 'package:geolocator/geolocator.dart';

import 'student_api.dart';

class AttendanceLocation {
  Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ApiException(
        'Vui lòng bật dịch vụ vị trí trên thiết bị rồi thử lại.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const ApiException(
        'Quyền vị trí đã bị tắt. Mở Cài đặt ứng dụng và cho phép truy cập vị trí.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const ApiException('Cần quyền vị trí để điểm danh đợt này.');
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      throw const ApiException(
        'Chưa lấy được vị trí hiện tại. Vui lòng kiểm tra GPS và thử lại.',
      );
    }
  }
}
