// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> openPrintableSheet(String html_, {String title = 'Grade sheet'}) async {
  try {
    final blob = html.Blob([html_], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final opened = html.window.open(url, '_blank');

    if (opened.closed ?? false) {
      html.Url.revokeObjectUrl(url);
      return false;
    }

    Future.delayed(const Duration(minutes: 1), () {
      html.Url.revokeObjectUrl(url);
    });
    return true;
  } catch (_) {
    return false;
  }
}