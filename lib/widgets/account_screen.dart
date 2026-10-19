import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'app_top_bar.dart';
import '../models/student_profile.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.profile});

  final StudentProfile profile;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(constraints.maxWidth, 480.0);
          final scale = width / 393;
          return SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12 * scale,
                    0,
                    12 * scale,
                    16 * scale,
                  ),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 196 * scale,
                          height: 196 * scale,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFE1EFF0),
                          ),
                        ),
                      ),
                      // Thẻ phủ lên phần viền nhạt nằm dưới mép trên của thẻ.
                      Padding(
                        padding: EdgeInsets.only(top: 112 * scale),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.fromLTRB(
                            14 * scale,
                            76 * scale,
                            14 * scale,
                            20 * scale,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16 * scale),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [AppTopBar.uehBlue, Color(0xFF003E49)],
                            ),
                          ),
                          child: DefaultTextStyle(
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16 * scale,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'SINH VIÊN',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13 * scale,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                SizedBox(height: 10 * scale),
                                Text(
                                  profile.fullName,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20 * scale,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 8 * scale),
                                Text(
                                  'MSSV: ${profile.studentId}',
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 26 * scale),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _field(
                                        'NGÀY SINH',
                                        profile.birthDate,
                                        scale,
                                      ),
                                    ),
                                    SizedBox(width: 14 * scale),
                                    Expanded(
                                      child: _field(
                                        'GIỚI TÍNH',
                                        profile.gender,
                                        scale,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 28 * scale),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _field(
                                        'KHOÁ',
                                        profile.course,
                                        scale,
                                      ),
                                    ),
                                    SizedBox(width: 14 * scale),
                                    Expanded(
                                      child: _field(
                                        'NƠI SINH',
                                        profile.birthPlace,
                                        scale,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 28 * scale),
                                _field(
                                  'HỆ ĐẠI HỌC - NIÊN HỌC',
                                  '${profile.program}\n-Niên học: ${profile.academicYears}',
                                  scale,
                                ),
                                SizedBox(height: 22 * scale),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _universityLogo(scale),
                                    _studentQr(scale),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(top: 8 * scale),
                          child: _portrait(scale),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _field(String label, String value, double scale) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 10 * scale, color: const Color(0xFFD7E8EA)),
      ),
      SizedBox(height: 12 * scale),
      Text(
        value,
        style: TextStyle(
          fontSize: 16 * scale,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  Widget _universityLogo(double scale) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white,
        Colors.white,
        Color(0xFFFF6F00),
        Color(0xFFFF6F00),
      ],
      stops: [0, .72, .72, 1],
    ).createShader(bounds),
    child: Image.asset(
      'assets/images/logo-primary.png',
      width: 102 * scale,
      semanticLabel: 'UEH University',
    ),
  );

  Widget _portrait(double scale) => SizedBox.square(
    dimension: 176 * scale,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(3 * scale),
        child: ClipOval(
          child: SizedBox.expand(
            child: profile.portraitUrl == null
                ? _placeholderPortrait(scale)
                : Image.network(
                    profile.portraitUrl!,
                    fit: BoxFit.cover,
                    semanticLabel: 'Ảnh sinh viên ${profile.fullName}',
                    errorBuilder: (_, error, stackTrace) =>
                        _placeholderPortrait(scale),
                  ),
          ),
        ),
      ),
    ),
  );

  Widget _placeholderPortrait(double scale) => Center(
    child: Icon(Icons.person, size: 96 * scale, color: AppTopBar.uehBlue),
  );

  Widget _studentQr(double scale) {
    final studentId = profile.studentId;
    return Container(
      width: 94 * scale,
      height: 94 * scale,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5 * scale),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 4)),
        ],
      ),
      child: studentId.isEmpty
          ? const Center(
              child: Text(
                'Chưa có mã số sinh viên',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTopBar.uehBlue, fontSize: 12),
              ),
            )
          : Semantics(
              label: 'Mã QR sinh viên $studentId',
              image: true,
              child: QrImageView(
                data: studentId,
                version: QrVersions.auto,
                padding: EdgeInsets.all(6 * scale),
                backgroundColor: Colors.white,
                gapless: true,
                semanticsLabel: 'Mã QR sinh viên $studentId',
              ),
            ),
    );
  }
}
