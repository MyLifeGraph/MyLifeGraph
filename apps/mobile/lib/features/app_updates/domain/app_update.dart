class InstalledAppVersion {
  const InstalledAppVersion(this.name, this.code, this.certificate);
  final String name;
  final int code;
  final String certificate;
}

class AppUpdate {
  const AppUpdate({required this.name, required this.code, required this.url});
  final String name;
  final int code;
  final Uri url;
}
