import 'dart:convert';
import 'dart:io';

/// Native (Non-Web) HTTP GET text fetcher
Future<String?> httpGetText(String url, {Duration timeout = const Duration(seconds: 8)}) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = timeout;
    final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) return null;
    return await utf8.decodeStream(response).timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    client?.close();
  }
}
