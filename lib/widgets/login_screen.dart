import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../controllers/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _studentId = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  void _showUnavailable(String method) {
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$method chưa được hỗ trợ. Vui lòng đăng nhập bằng MSSV và mật khẩu.',
          ),
        ),
      );
  }

  Widget _emailButton(String label, String method) => OutlinedButton(
    onPressed: widget.auth.busy || widget.auth.initializing
        ? null
        : () => _showUnavailable(method),
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFFFF6F00),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFFF6F00)),
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    child: Text(label, textAlign: TextAlign.center),
  );

  Future<void> _submit() async {
    if (widget.auth.busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await widget.auth.login(_studentId.text, _password.text);
    if (mounted && widget.auth.isLoggedIn) {
      _password.clear();
      TextInput.finishAutofillContext(shouldSave: false);
    }
  }

  @override
  void dispose() {
    _studentId.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.auth,
    builder: (context, _) => ColoredBox(
      color: const Color(0xFFFCF8FD),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                minHeight: constraints.maxHeight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/images/nso-splash-landscape-1499x999.png',
                    height: (constraints.maxHeight * .29).clamp(135.0, 230.0),
                    fit: BoxFit.cover,
                    semanticLabel: 'Đại học UEH',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                    child: AutofillGroup(
                      onDisposeAction: AutofillContextAction.cancel,
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Chào mừng đến với UEH',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Nơi đào tạo nhà quản lý và doanh nhân thành đạt',
                              style: TextStyle(
                                fontSize: 15,
                                color: Color(0xFF727076),
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _studentId,
                              enabled: !widget.auth.busy,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Mã số sinh viên',
                                hintText: 'Nhập MSSV',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Vui lòng nhập mã số sinh viên.'
                                  : null,
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _password,
                              enabled: !widget.auth.busy,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Mật khẩu',
                                hintText: 'Nhập mật khẩu',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Hiện mật khẩu'
                                      : 'Ẩn mật khẩu',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Vui lòng nhập mật khẩu.'
                                  : null,
                            ),
                            if (widget.auth.error != null) ...[
                              const SizedBox(height: 16),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  widget.auth.error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),
                            if (widget.auth.logoutNeedsRetry)
                              TextButton(
                                onPressed: widget.auth.busy
                                    ? null
                                    : widget.auth.logout,
                                child: const Text('Thử đăng xuất lại'),
                              ),
                            FilledButton(
                              onPressed:
                                  widget.auth.busy || widget.auth.initializing
                                  ? null
                                  : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6F00),
                                minimumSize: const Size.fromHeight(52),
                              ),
                              child: widget.auth.busy
                                  ? const SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'ĐĂNG NHẬP',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 14),
                            _emailButton(
                              'ĐĂNG NHẬP BẰNG EMAIL UEH',
                              'Đăng nhập bằng email UEH',
                            ),
                            const SizedBox(height: 14),
                            _emailButton(
                              'ĐĂNG NHẬP BẰNG EMAIL KHÁCH',
                              'Đăng nhập bằng email khách',
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton(
                              onPressed:
                                  widget.auth.busy || widget.auth.initializing
                                  ? null
                                  : () => _showUnavailable(
                                      'Đăng nhập bằng Apple',
                                    ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                surfaceTintColor: Colors.transparent,
                                elevation: 0,
                                minimumSize: const Size.fromHeight(52),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FaIcon(FontAwesomeIcons.apple, size: 26),
                                  SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'Sign in with Apple',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
