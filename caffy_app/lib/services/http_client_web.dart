// 웹 플랫폼용 HTTP 클라이언트 (withCredentials 활성화)
import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

http.Client createHttpClient() {
  final client = BrowserClient();
  client.withCredentials = true; // CORS credentials 활성화
  return client;
}
