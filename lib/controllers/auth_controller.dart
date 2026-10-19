import 'package:flutter/foundation.dart';

import '../models/student_profile.dart';
import '../services/student_api.dart';

class AuthController extends ChangeNotifier {
  AuthController({StudentApi? api}) : api = api ?? StudentApi() {
    this.api.onSessionExpired = () {
      profile = null;
      error = 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
      _notify();
    };
  }
  final StudentApi api;
  StudentProfile? profile;
  bool busy = false;
  bool initializing = true;
  String? error;
  bool logoutNeedsRetry = false;
  bool _disposed = false;
  bool get isLoggedIn => api.hasSession;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await api.restore();
      if (api.hasSession) profile = await api.studentInfo();
    } catch (e) {
      error = _message(e);
    } finally {
      initializing = false;
      _notify();
    }
  }

  Future<void> login(String studentId, String password) async {
    if (busy || initializing) return;
    busy = true;
    error = null;
    _notify();
    try {
      await api.login(studentId, password);
      profile = await api.studentInfo();
    } catch (e) {
      error = _message(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> reloadProfile() async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      profile = await api.studentInfo();
    } catch (e) {
      error = _message(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> logout() async {
    if (busy) return;
    busy = true;
    profile = null;
    error = null;
    logoutNeedsRetry = false;
    _notify();
    try {
      await api.logout();
    } catch (_) {
      logoutNeedsRetry = true;
      error = 'Không thể xóa phiên đã lưu trên thiết bị. Vui lòng thử đăng xuất lại.';
    } finally {
      busy = false;
      _notify();
    }
  }

  String _message(Object e) => e is ApiException
      ? e.message
      : 'Không thể đọc hoặc lưu phiên đăng nhập. Vui lòng thử lại.';

  @override
  void dispose() {
    _disposed = true;
    api.onSessionExpired = null;
    api.close();
    super.dispose();
  }
}
