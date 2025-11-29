// 웹에서 withCredentials를 지원하는 HTTP 클라이언트
// 조건부 import 사용
export 'http_client_stub.dart'
    if (dart.library.html) 'http_client_web.dart';
