import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AttachmentHelper {
  AttachmentHelper._();

  /// Downloads a remote attachment and opens it using the system's default app handler.
  static Future<void> downloadAndOpen({
    required String fileUrl,
    required String fileName,
    Function(double progress)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final localFile = File('${tempDir.path}/$fileName');

      // Check if file is already cached/downloaded
      if (await localFile.exists()) {
        final result = await OpenFilex.open(localFile.path);
        if (result.type != ResultType.done) {
          throw result.message;
        }
        return;
      }

      // Download from Firebase Storage URL
      final response = await http.get(Uri.parse(fileUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download file from Storage.');
      }

      await localFile.writeAsBytes(response.bodyBytes);

      // Open via native system intent / deep link
      final result = await OpenFilex.open(localFile.path);
      if (result.type != ResultType.done) {
        throw result.message;
      }
    } catch (e) {
      throw Exception('Could not open file: $e');
    }
  }

  /// Direct external browser launching for URLs.
  static Future<void> openInBrowser(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw 'launchUrl returned false';
      }
    } catch (e) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch browser for $url: $e');
      }
    }
  }
}
