import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

class AppController extends ChangeNotifier {
  static const defaultBaseUrl = 'http://127.0.0.1:8765';
  SharedPreferences? _prefs;
  ApiClient? api;
  String baseUrl = defaultBaseUrl;
  String? token;
  AppUser? user;
  bool initialized = false;
  bool busy = false;
  String? lastError;
  List<JsonMap> categories = [];
  List<JsonMap> assets = [];
  List<JsonMap> providers = [];
  List<JsonMap> profiles = [];
  List<JsonMap> jobs = [];
  List<JsonMap> users = [];
  JsonMap settings = {};
  int assetTotal = 0;
  String assetSearch = '';
  int? assetCategoryId;
  String assetStatus = '';
  Timer? _jobTimer;

  bool get loggedIn => token != null && user != null && api != null;
  bool get isAdmin => user?.isAdmin ?? false;
  List<JsonMap> get activeCategories =>
      categories.where((item) => asBool(item['enabled'], true)).toList();
  List<JsonMap> get currentJobs {
    final seen = <int>{};
    return jobs.where((job) {
      final id = asInt(job['asset_id']);
      if (seen.contains(id)) return false;
      seen.add(id);
      return true;
    }).toList();
  }

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs?.getString('ai_lib_base_url') ?? defaultBaseUrl;
    token = _prefs?.getString('ai_lib_token');
    final cachedUser = _prefs?.getString('ai_lib_user');
    if (cachedUser != null) {
      try {
        user = AppUser.fromJson(jsonDecode(cachedUser) as JsonMap);
      } catch (_) {
        token = null;
      }
    }
    api = ApiClient(baseUrl: baseUrl, token: token);
    initialized = true;
    notifyListeners();
    if (loggedIn) {
      try {
        await refreshAll();
        _startJobPolling();
      } catch (error) {
        lastError = _message(error);
        notifyListeners();
      }
    }
  }

  Future<Session> login(String url, String username, String password) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final nextApi = ApiClient(baseUrl: url);
      final response =
          await nextApi.post(
                '/api/v1/auth/login',
                body: {'username': username, 'password': password},
              )
              as JsonMap;
      token = asString(response['access_token']);
      baseUrl = nextApi.baseUrl;
      user = AppUser.fromJson(response);
      api = ApiClient(baseUrl: baseUrl, token: token);
      await _saveSession();
      await refreshAll();
      _startJobPolling();
      return Session(token: token!, user: user!);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _jobTimer?.cancel();
    token = null;
    user = null;
    api = ApiClient(baseUrl: baseUrl);
    categories = [];
    assets = [];
    providers = [];
    profiles = [];
    jobs = [];
    users = [];
    await _prefs?.remove('ai_lib_token');
    await _prefs?.remove('ai_lib_user');
    notifyListeners();
  }

  Future<void> setBaseUrl(String value) async {
    final next = ApiClient(baseUrl: value);
    baseUrl = next.baseUrl;
    api = ApiClient(baseUrl: baseUrl, token: token);
    await _prefs?.setString('ai_lib_base_url', baseUrl);
    notifyListeners();
  }

  Future<void> refreshAll() async {
    if (!loggedIn) return;
    final futures = <Future<void>>[
      loadCategories(),
      loadAssets(),
      loadProviders(),
      loadProfiles(),
    ];
    if (isAdmin) futures.addAll([loadJobs(), loadUsers(), loadSettings()]);
    await Future.wait(futures);
  }

  Future<void> loadCategories() async {
    final data = await api!.get('/api/v1/categories');
    categories = (data as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    notifyListeners();
  }

  Future<void> loadAssets({
    int page = 1,
    String search = '',
    int? categoryId,
    String? status,
    bool applyFilters = false,
  }) async {
    if (applyFilters && page == 1) {
      assetSearch = search;
      assetCategoryId = categoryId;
      assetStatus = status ?? '';
    }
    final effectiveSearch = applyFilters ? search : assetSearch;
    final effectiveCategoryId = applyFilters ? categoryId : assetCategoryId;
    final effectiveStatus = applyFilters ? (status ?? '') : assetStatus;
    final query = <String, Object?>{
      'page': page,
      'page_size': 80,
      if (effectiveSearch.trim().isNotEmpty) 'search': effectiveSearch.trim(),
      if (effectiveStatus.isNotEmpty) 'status': effectiveStatus,
    };
    if (effectiveCategoryId != null) query['category_id'] = effectiveCategoryId;
    final data = PageResult.fromJson(
      await api!.get('/api/v1/assets', query: query) as JsonMap,
    );
    if (page == 1) {
      assets = data.items;
    } else {
      assets = [...assets, ...data.items];
    }
    assetTotal = data.total;
    notifyListeners();
  }

  Future<void> loadProviders() async {
    final data = await api!.get('/api/v1/providers');
    providers = (data as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    notifyListeners();
  }

  Future<void> loadProfiles() async {
    final data = await api!.get('/api/v1/prompt-profiles');
    profiles = (data as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    notifyListeners();
  }

  Future<void> loadJobs() async {
    if (!isAdmin) return;
    final data = await api!.get('/api/v1/jobs');
    jobs = (data as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    notifyListeners();
  }

  Future<void> loadUsers() async {
    if (!isAdmin) return;
    final data = await api!.get('/api/v1/users');
    users = (data as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    notifyListeners();
  }

  Future<void> loadSettings() async {
    if (!isAdmin) return;
    settings = Map<String, dynamic>.from(
      await api!.get('/api/v1/settings') as Map,
    );
    notifyListeners();
  }

  Future<JsonMap> createCategory(JsonMap body) async {
    final result = Map<String, dynamic>.from(
      await api!.post('/api/v1/categories', body: body) as Map,
    );
    await loadCategories();
    return result;
  }

  Future<JsonMap> updateCategory(int id, JsonMap body) async {
    final result = Map<String, dynamic>.from(
      await api!.patch('/api/v1/categories/$id', body),
    );
    await loadCategories();
    return result;
  }

  Future<void> deleteCategory(int id) async {
    await api!.delete('/api/v1/categories/$id');
    await loadCategories();
  }

  Future<JsonMap> createProvider(JsonMap body) async {
    final result = Map<String, dynamic>.from(
      await api!.post('/api/v1/providers', body: body) as Map,
    );
    await loadProviders();
    return result;
  }

  Future<JsonMap> updateProvider(int id, JsonMap body) async {
    final result = Map<String, dynamic>.from(
      await api!.patch('/api/v1/providers/$id', body),
    );
    await loadProviders();
    return result;
  }

  Future<JsonMap> testProvider(int id) async => Map<String, dynamic>.from(
    await api!.post('/api/v1/providers/$id/test') as Map,
  );

  Future<JsonMap> pullProviderModels(int id) async {
    final result = Map<String, dynamic>.from(
      await api!.post('/api/v1/providers/$id/models/pull') as Map,
    );
    await loadProviders();
    return result;
  }

  Future<void> deleteProvider(int id) async {
    await api!.delete('/api/v1/providers/$id');
    await loadProviders();
  }

  Future<JsonMap> createProfile(JsonMap body) async {
    final result = Map<String, dynamic>.from(
      await api!.post('/api/v1/prompt-profiles', body: body) as Map,
    );
    await loadProfiles();
    return result;
  }

  Future<JsonMap> updateProfile(int id, JsonMap body) async {
    final result = Map<String, dynamic>.from(
      await api!.patch('/api/v1/prompt-profiles/$id', body),
    );
    await loadProfiles();
    return result;
  }

  Future<JsonMap> updateAsset(int id, JsonMap body) async {
    final result = Map<String, dynamic>.from(
      await api!.patch('/api/v1/assets/$id', body),
    );
    await loadAssets();
    return result;
  }

  Future<void> restoreAsset(int id) async {
    await api!.post('/api/v1/assets/$id/restore');
    await loadAssets();
  }

  Future<void> reanalyzeAsset(int id) async {
    await api!.post('/api/v1/assets/$id/reanalyze');
    await Future.wait([loadAssets(), if (isAdmin) loadJobs()]);
  }

  Future<void> deleteAsset(int id) async {
    await api!.delete('/api/v1/assets/$id');
    await loadAssets();
  }

  Future<JsonMap> randomPrompts(
    List<int> categoryIds,
    int count,
    int seed,
  ) async => Map<String, dynamic>.from(
    await api!.post(
          '/api/v1/random',
          body: {'category_ids': categoryIds, 'count': count, 'seed': seed},
        )
        as Map,
  );

  Future<JsonMap> createUser(JsonMap body) async {
    final result = Map<String, dynamic>.from(
      await api!.post('/api/v1/users', body: body) as Map,
    );
    await loadUsers();
    return result;
  }

  Future<JsonMap> updateUser(int id, JsonMap body) async {
    final result = Map<String, dynamic>.from(
      await api!.patch('/api/v1/users/$id', body),
    );
    await loadUsers();
    if (id == user?.id) {
      user = AppUser.fromJson(result);
      await _saveSession();
    }
    return result;
  }

  Future<void> deleteUser(int id) async {
    await api!.delete('/api/v1/users/$id');
    await loadUsers();
  }

  Future<void> updateSettings(String comfyuiKey) async {
    await api!.patch('/api/v1/settings', {'comfyui_api_key': comfyuiKey});
    await loadSettings();
  }

  Future<JsonMap> uploadAssets(
    List<({String name, Uint8List bytes, String filename, String contentType})>
    files, {
    required int categoryId,
    int? providerId,
    String? modelName,
    int? profileId,
    bool force = false,
  }) async {
    final fields = <String, String>{
      'category_id': '$categoryId',
      'force': '$force',
    };
    if (providerId != null) fields['provider_id'] = '$providerId';
    if (modelName != null && modelName.isNotEmpty) {
      fields['model_name'] = modelName;
    }
    if (profileId != null) fields['prompt_profile_id'] = '$profileId';
    final result = await api!.upload(files, fields);
    await Future.wait([loadAssets(), if (isAdmin) loadJobs()]);
    return result;
  }

  Future<void> saveImageToPhotos(String url, {String? name}) async {
    final bytes = await api!.download(url);
    final result = await ImageGallerySaverPlus.saveImage(
      bytes,
      quality: 95,
      name: name ?? 'AI-Lib-${DateTime.now().millisecondsSinceEpoch}',
    );
    if (result is Map &&
        (result['isSuccess'] == false || result['success'] == false)) {
      throw ApiException('保存到相册失败');
    }
  }

  Future<void> shareDownload(
    String path,
    Uint8List bytes,
    String filename,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = await _writeBytes(dir.path, filename, bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file)], text: 'AI-Lib 导出文件'),
    );
  }

  Future<String> _writeBytes(
    String directory,
    String filename,
    Uint8List bytes,
  ) async {
    final file = File('$directory/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> shareBackup() async {
    final bytes = await api!.download('/api/v1/backup');
    await shareDownload('', bytes, 'ai-lib-backup.zip');
  }

  Future<void> shareCategoryExport(int categoryId) async {
    final bytes = await api!.download(
      '/api/v1/export',
      query: {'category_id': categoryId},
    );
    await shareDownload('', bytes, 'ai-lib-category-$categoryId.json');
  }

  Future<void> _saveSession() async {
    await _prefs?.setString('ai_lib_base_url', baseUrl);
    if (token != null) await _prefs?.setString('ai_lib_token', token!);
    if (user != null) {
      await _prefs?.setString('ai_lib_user', jsonEncode(user!.toJson()));
    }
  }

  void _startJobPolling() {
    _jobTimer?.cancel();
    if (!isAdmin) return;
    _jobTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        await loadJobs();
        if (currentJobs.any(
          (job) => job['status'] == 'completed' || job['status'] == 'failed',
        )) {
          await loadAssets();
        }
      } catch (_) {}
    });
  }

  String _message(Object error) =>
      error is ApiException ? error.message : '网络连接失败，请检查服务地址和网络';

  @override
  void dispose() {
    _jobTimer?.cancel();
    super.dispose();
  }
}
