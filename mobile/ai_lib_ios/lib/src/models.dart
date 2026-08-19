typedef JsonMap = Map<String, dynamic>;

int asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true' || value == '1';
  return fallback;
}

String asString(Object? value, [String fallback = '']) =>
    value?.toString() ?? fallback;

class PageResult {
  const PageResult({
    required this.items,
    required this.total,
    required this.page,
  });
  final List<JsonMap> items;
  final int total;
  final int page;

  factory PageResult.fromJson(JsonMap json) => PageResult(
    items: (json['items'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(),
    total: asInt(json['total']),
    page: asInt(json['page'], 1),
  );
}

class AppUser {
  AppUser({
    required this.id,
    required this.username,
    required this.role,
    required this.enabled,
    this.avatarUrl = '',
    this.categoryIds = const [],
    this.categoryNames = const [],
  });
  final int id;
  final String username;
  final String role;
  final bool enabled;
  final String avatarUrl;
  final List<int> categoryIds;
  final List<String> categoryNames;

  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(JsonMap json) => AppUser(
    id: asInt(json['id'] ?? json['user_id']),
    username: asString(json['username']),
    role: asString(json['role'], 'user'),
    enabled: asBool(json['enabled'], true),
    avatarUrl: asString(json['avatar_url']),
    categoryIds: (json['category_ids'] as List? ?? []).map(asInt).toList(),
    categoryNames: (json['category_names'] as List? ?? [])
        .map(asString)
        .toList(),
  );

  JsonMap toJson() => {
    'id': id,
    'username': username,
    'role': role,
    'enabled': enabled,
    'avatar_url': avatarUrl,
    'category_ids': categoryIds,
    'category_names': categoryNames,
  };
}

class Session {
  const Session({required this.token, required this.user});
  final String token;
  final AppUser user;
}
