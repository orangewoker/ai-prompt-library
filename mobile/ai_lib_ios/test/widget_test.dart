import 'package:ai_lib_ios/src/api_client.dart';
import 'package:ai_lib_ios/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('服务地址会自动规范化', () {
    final client = ApiClient(baseUrl: 'http://192.168.1.20:8765/api/v1/');
    expect(client.baseUrl, 'http://192.168.1.20:8765');
    expect(
      client.uri('/api/v1/health').toString(),
      'http://192.168.1.20:8765/api/v1/health',
    );
  });

  test('登录用户模型兼容 login 响应', () {
    final user = AppUser.fromJson({
      'user_id': 7,
      'username': 'alice',
      'role': 'admin',
      'category_ids': [1, 2],
    });
    expect(user.id, 7);
    expect(user.isAdmin, isTrue);
    expect(user.categoryIds, [1, 2]);
  });

  test('素材分页结果可解析', () {
    final page = PageResult.fromJson({
      'items': [
        {'id': 1},
      ],
      'total': 1,
      'page': 1,
    });
    expect(page.total, 1);
    expect(page.items.single['id'], 1);
  });
}
