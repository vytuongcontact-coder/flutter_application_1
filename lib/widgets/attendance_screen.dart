import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'app_top_bar.dart';
import '../services/student_api.dart';
import '../services/attendance_location.dart';
import 'scan_code_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.api, this.location});
  final StudentApi api;
  final AttendanceLocation? location;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  bool _busy = false;
  Map<String, dynamic>? _result;
  String? _error;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (_busy) return;
    final code = _codeController.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      _codeFocus.requestFocus();
      _showMessage('Mã điểm danh gồm 6 chữ cái hoặc chữ số.');
      return;
    }
    _codeFocus.unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      Map<String, dynamic> result;
      try {
        result = await widget.api.attend(code);
      } on ApiException catch (e) {
        // The API has no session-info endpoint. Only request GPS after the
        // documented missing-location error; other failures must not retry.
        if (e.statusCode != 400 ||
            !e.message.contains('latitude') ||
            !e.message.contains('longitude')) {
          rethrow;
        }
        final position = await (widget.location ?? AttendanceLocation())
            .current();
        if (!mounted) return;
        result = await widget.api.attend(
          code,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Không thể hoàn tất điểm danh. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanCodeScreen()));
    if (!mounted || code == null) return;
    setState(() {
      _codeController.text = code;
      _result = null;
      _error = null;
    });
    _showMessage('Đã đọc mã. Nhấn Điểm danh để xác nhận.');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFFCF8FD),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Giữ tỷ lệ của mẫu trên điện thoại và giới hạn độ rộng trên tablet.
        final width = math.min(constraints.maxWidth, 480.0);
        final scale = width / 393;
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: SizedBox(
                width: width,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 40 * scale,
                    bottom: 100 * scale,
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20 * scale),
                        child: Text(
                          'Vui lòng nhập hoặc quét mã để điểm danh',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTopBar.uehBlue,
                            fontSize: 17 * scale,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(height: 60 * scale),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: width * .1),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Nhập mã điểm danh',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: const Color(0xFF858285),
                                fontSize: 14 * scale,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 8 * scale),
                            TextField(
                              controller: _codeController,
                              enabled: !_busy,
                              maxLength: 6,
                              textCapitalization: TextCapitalization.characters,
                              focusNode: _codeFocus,
                              textAlign: TextAlign.center,
                              textInputAction: TextInputAction.done,
                              autocorrect: false,
                              enableSuggestions: false,
                              onSubmitted: (_) => _submit(),
                              cursorColor: AppTopBar.uehBlue,
                              style: TextStyle(fontSize: 14 * scale),
                              decoration: InputDecoration(
                                hintText: 'Nhập mã ở đây',
                                hintStyle: const TextStyle(
                                  color: Color(0xFFDFDDE0),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 14 * scale,
                                ),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF858285),
                                  ),
                                ),
                                focusedBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppTopBar.uehBlue,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 36 * scale),
                            Text(
                              'Hoặc',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: const Color(0xFFBDBABD),
                                fontSize: 16 * scale,
                              ),
                            ),
                            SizedBox(height: 20 * scale),
                            _scanButton(
                              label: 'Quét mã QR Code',
                              icon: Icon(
                                Icons.qr_code_scanner,
                                size: 25 * scale,
                              ),
                              scale: scale,
                            ),
                            SizedBox(height: 14 * scale),
                            _scanButton(
                              label: 'Quét mã Barcode',
                              icon: _framedIcon(
                                FontAwesomeIcons.barcode,
                                scale,
                              ),
                              scale: scale,
                            ),
                            SizedBox(height: 14 * scale),
                            _scanButton(
                              label: 'Xác thực khuôn mặt',
                              icon: _framedIcon(
                                FontAwesomeIcons.solidUser,
                                scale,
                              ),
                              scale: scale,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Xác thực khuôn mặt sẽ được hỗ trợ sau.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                              ),
                            if (_result != null)
                              Container(
                                margin: const EdgeInsets.only(top: 20),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3F3EB),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        color: Color(0xFF167044),
                                        size: 32,
                                      ),
                                      Text(
                                        _result!['message']?.toString() ??
                                            'Điểm danh thành công.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (_result!['sessionName'] != null)
                                        Text(
                                          _result!['sessionName'].toString(),
                                          textAlign: TextAlign.center,
                                        ),
                                      if (_result!['checkedInAt'] != null)
                                        Text(
                                          'Giờ Việt Nam: ${_result!['checkedInAt'].toString().replaceFirst('T', ' ').split('.').first}',
                                          textAlign: TextAlign.center,
                                        ),
                                      if (_result!['distanceMeters'] is num)
                                        Text(
                                          'Khoảng cách: ${(_result!['distanceMeters'] as num).toStringAsFixed(1)} m',
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            SizedBox(height: 38 * scale),
                            ElevatedButton(
                              onPressed: _busy ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTopBar.uehBlue,
                                foregroundColor: Colors.white,
                                surfaceTintColor: Colors.transparent,
                                elevation: 3,
                                shadowColor: Colors.black38,
                                minimumSize: Size.fromHeight(48 * scale),
                                shape: const StadiumBorder(),
                                textStyle: TextStyle(
                                  fontSize: 18 * scale,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              child: _busy
                                  ? const SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Điểm danh'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _framedIcon(FaIconData icon, double scale) => SizedBox.square(
    dimension: 26 * scale,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.crop_free_rounded, size: 26 * scale),
        FaIcon(icon, size: 14 * scale),
      ],
    ),
  );

  Widget _scanButton({
    required String label,
    required Widget icon,
    required double scale,
  }) => OutlinedButton(
    onPressed: _busy || label == 'Xác thực khuôn mặt' ? null : _scan,
    style: OutlinedButton.styleFrom(
      foregroundColor: AppTopBar.uehBlue,
      backgroundColor: Colors.white,
      minimumSize: Size.fromHeight(48 * scale),
      padding: EdgeInsets.symmetric(
        horizontal: 18 * scale,
        vertical: 10 * scale,
      ),
      side: const BorderSide(color: AppTopBar.uehBlue),
      shape: const StadiumBorder(),
      textStyle: TextStyle(fontSize: 16 * scale, letterSpacing: 1.5),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Align(alignment: Alignment.centerLeft, child: icon),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 26 * scale),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ],
    ),
  );
}
