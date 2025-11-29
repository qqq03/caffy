// 네이티브 플랫폼용 HTTP 클라이언트 (Android, iOS, Desktop)
import 'package:http/http.dart' as http;

http.Client createHttpClient() {
  return http.Client();
}
