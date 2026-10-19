import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanCodeScreen extends StatefulWidget {
  const ScanCodeScreen({super.key});
  @override
  State<ScanCodeScreen> createState() => _ScanCodeScreenState();
}

class _ScanCodeScreenState extends State<ScanCodeScreen>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController();
  bool _returned = false;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission || _returned) return;
    if (state == AppLifecycleState.resumed) {
      _controller.start();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét mã điểm danh')),
    body: Stack(
      children: [
        MobileScanner(
          controller: _controller,
          errorBuilder: (context, error) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Không mở được camera. Hãy cấp quyền camera trong Cài đặt hoặc quay lại để nhập mã.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          onDetect: (capture) {
            if (_returned) return;
            for (final barcode in capture.barcodes) {
              final code = barcode.rawValue?.trim().toUpperCase();
              if (code != null && RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
                _returned = true;
                _controller.stop();
                Navigator.of(context).pop(code);
                return;
              }
            }
            if (!_invalid) setState(() => _invalid = true);
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _invalid
                    ? 'Mã không hợp lệ. Hãy quét mã đợt gồm 6 chữ cái hoặc chữ số.'
                    : 'Đưa mã QR hoặc Barcode của đợt điểm danh vào camera.',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
