class StudentProfile {
  const StudentProfile({
    required this.fullName,
    required this.birthDate,
    required this.gender,
    required this.course,
    required this.birthPlace,
    required this.program,
    required this.academicYears,
    required this.studentId,
    this.portraitUrl,
  });

  final String fullName, birthDate, gender, course, birthPlace;
  final String program, academicYears, studentId;
  final String? portraitUrl;

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    String field(String key) => json[key]?.toString().trim() ?? '';
    String display(String key) =>
        field(key).isEmpty ? 'Chưa cập nhật' : field(key);
    if (field('mssv').isEmpty || field('hoVaTen').isEmpty) {
      throw const FormatException('Thiếu thông tin sinh viên.');
    }
    final date = DateTime.tryParse(field('ngaySinh'));
    final image = Uri.tryParse(field('hinhDaiDien'));
    return StudentProfile(
      studentId: field('mssv'),
      fullName: field('hoVaTen'),
      birthDate: date == null
          ? 'Chưa cập nhật'
          : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
      gender: switch (json['gioiTinh']) {
        true => 'Nam',
        false => 'Nữ',
        _ => 'Chưa cập nhật',
      },
      course: display('nienKhoa'),
      birthPlace: display('noiSinh'),
      program: display('heDaoTao'),
      academicYears: display('nienHoc'),
      portraitUrl: image?.scheme == 'https' && image!.hasAuthority
          ? image.toString()
          : null,
    );
  }
}
