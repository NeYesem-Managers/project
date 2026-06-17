import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/constants/app_colors.dart';

// Android emülatörde localhost yerine 10.0.2.2 kullanılır (host PC'ye erişim)
String _defaultBackendHost() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return '10.0.2.2';
  }
  return 'localhost';
}

String resolvedApiBaseUrl() {
  const envUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (envUrl.isNotEmpty) return envUrl;
  return 'http://${_defaultBackendHost()}:3000/api';
}

// Kullanıcının seçtiği konum tercihleri
class LocationPrefs {
  final String city;
  final String district;
  final String cityLabel;
  final String districtLabel;

  const LocationPrefs({
    required this.city,
    required this.district,
    required this.cityLabel,
    required this.districtLabel,
  });

  static const _kCity = 'loc_city';
  static const _kDistrict = 'loc_district';
  static const _kCityLabel = 'loc_city_label';
  static const _kDistrictLabel = 'loc_district_label';

  static Future<LocationPrefs?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final city = prefs.getString(_kCity);
    if (city == null || city.isEmpty) return null;
    return LocationPrefs(
      city: city,
      district: prefs.getString(_kDistrict) ?? '',
      cityLabel: prefs.getString(_kCityLabel) ?? city,
      districtLabel: prefs.getString(_kDistrictLabel) ?? '',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCity, city);
    await prefs.setString(_kDistrict, district);
    await prefs.setString(_kCityLabel, cityLabel);
    await prefs.setString(_kDistrictLabel, districtLabel);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCity);
    await prefs.remove(_kDistrict);
    await prefs.remove(_kCityLabel);
    await prefs.remove(_kDistrictLabel);
  }

  String get displayLabel {
    if (districtLabel.isNotEmpty) return '$districtLabel / $cityLabel';
    return cityLabel;
  }
}

void main() {
  runApp(const NeYesemDemoApp());
}

class NeYesemDemoApp extends StatelessWidget {
  const NeYesemDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeYesem Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff5f5f5),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xfff5f5f5),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class MyApp extends NeYesemDemoApp {
  const MyApp({super.key});
}

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? resolvedApiBaseUrl();

  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final uri = Uri.parse('$baseUrl$path');
    if (queryParameters == null) {
      return uri;
    }
    return uri.replace(queryParameters: queryParameters);
  }

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _uri(path, queryParameters);
    final headers = {'Content-Type': 'application/json'};

    late http.Response response;
    try {
      if (method == 'POST') {
        response = await http
            .post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 25));
      } else if (method == 'PUT') {
        response = await http
            .put(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 25));
      } else {
        response = await http.get(uri).timeout(const Duration(seconds: 25));
      }
    } catch (error) {
      throw ApiException(
        'Backend bağlantısı kurulamadı. Backend çalışıyor mu?',
      );
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message']?.toString()
          : null;
      throw ApiException(
        message ?? 'Backend hata verdi: ${response.statusCode}',
      );
    }

    return decoded;
  }

  Future<UserSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final data = await _request(
      '/auth/register',
      method: 'POST',
      body: {'name': name, 'email': email, 'password': password},
    );
    return UserSession.fromJson(data as Map<String, dynamic>);
  }

  Future<UserSession> login({
    required String email,
    required String password,
  }) async {
    final data = await _request(
      '/auth/login',
      method: 'POST',
      body: {'email': email, 'password': password},
    );
    return UserSession.fromJson(data as Map<String, dynamic>);
  }

  Future<UserProfile> getProfile(String userId) async {
    final data = await _request('/profile/$userId');
    return UserProfile.fromJson(data as Map<String, dynamic>);
  }

  Future<UserProfile> updateProfile(
    String userId, {
    required String name,
    required List<String> allergies,
    required String dietPreference,
    required int? calorieTarget,
    required List<String> favoriteCategories,
  }) async {
    final data = await _request(
      '/profile/$userId',
      method: 'PUT',
      body: {
        'name': name,
        'allergies': allergies,
        'dietPreference': dietPreference,
        'calorieTarget': calorieTarget,
        'favoriteCategories': favoriteCategories,
      },
    );
    final map = data as Map<String, dynamic>;
    return UserProfile.fromJson(map['user'] as Map<String, dynamic>);
  }

  Future<List<CityModel>> getCities() async {
    final data = await _request('/cities');
    if (data is! List) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(CityModel.fromJson)
        .toList();
  }

  Future<List<DistrictModel>> getDistricts(String city) async {
    final data = await _request('/districts', queryParameters: {'city': city});
    if (data is! List) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(DistrictModel.fromJson)
        .toList();
  }

  Future<PagedResult> getDeals({
    int page = 1,
    int limit = 20,
    String sort = '',
    String city = '',
    String district = '',
    double? minPrice,
    double? maxPrice,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (sort.isNotEmpty) params['sort'] = sort;
    if (city.isNotEmpty) params['city'] = city;
    if (district.isNotEmpty) params['district'] = district;
    if (minPrice != null) params['minPrice'] = '$minPrice';
    if (maxPrice != null) params['maxPrice'] = '$maxPrice';
    final data = await _request('/deals', queryParameters: params);
    return PagedResult.fromJson(data);
  }

  Future<PagedResult> searchProducts(
    String query, {
    int page = 1,
    int limit = 20,
    String sort = '',
    String city = '',
    String district = '',
    double? minPrice,
    double? maxPrice,
  }) async {
    final params = <String, String>{
      'q': query,
      'page': '$page',
      'limit': '$limit',
    };
    if (sort.isNotEmpty) params['sort'] = sort;
    if (city.isNotEmpty) params['city'] = city;
    if (district.isNotEmpty) params['district'] = district;
    if (minPrice != null) params['minPrice'] = '$minPrice';
    if (maxPrice != null) params['maxPrice'] = '$maxPrice';
    final data = await _request('/search', queryParameters: params);
    return PagedResult.fromJson(data);
  }

  Future<List<Product>> getSuspiciousDiscounts({String city = '', String district = ''}) async {
    final params = <String, String>{};
    if (city.isNotEmpty) params['city'] = city;
    if (district.isNotEmpty) params['district'] = district;
    final data = await _request('/suspicious-discounts', queryParameters: params.isNotEmpty ? params : null);
    return _parseProducts(data);
  }

  Future<CompareResult> compare(String query, {String city = '', String district = ''}) async {
    final params = <String, String>{'query': query};
    if (city.isNotEmpty) params['city'] = city;
    if (district.isNotEmpty) params['district'] = district;
    final data = await _request('/compare', queryParameters: params);
    return CompareResult.fromJson(data as Map<String, dynamic>);
  }

  Future<Product> getProductAnalysis(String productId, Product fallback) async {
    final data = await _request('/products/$productId/analysis');
    final map = data as Map<String, dynamic>;
    final product = map['product'];
    if (product is Map<String, dynamic>) {
      return Product.fromJson(product);
    }
    return fallback;
  }

  List<Product> _parseProducts(dynamic data) {
    if (data is! List) {
      return [];
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(Product.fromJson)
        .toList();
  }
}

Future<void> launchPartnerUrl(BuildContext context, Product product) async {
  final rawUrl = product.partnerUrl.trim();
  if (rawUrl.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bu ürün için partner bağlantısı bulunamadı.'),
      ),
    );
    return;
  }

  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !uri.hasScheme) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Partner bağlantısı geçerli değil.')),
    );
    return;
  }

  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Partner bağlantısı açılamadı: ${product.platform}'),
        ),
      );
    }
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Partner bağlantısı açılamadı: ${product.platform}'),
      ),
    );
  }
}

class CityModel {
  final String key;
  final String label;

  const CityModel({required this.key, required this.label});

  factory CityModel.fromJson(Map<String, dynamic> json) {
    return CityModel(
      key: '${json['key'] ?? ''}',
      label: '${json['label'] ?? json['key'] ?? ''}',
    );
  }
}

class DistrictModel {
  final String key;
  final String label;
  final int count;

  const DistrictModel({required this.key, required this.label, this.count = 0});

  factory DistrictModel.fromJson(Map<String, dynamic> json) {
    return DistrictModel(
      key: '${json['key'] ?? ''}',
      label: '${json['label'] ?? json['key'] ?? ''}',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class UserSession {
  final String userId;
  final UserProfile user;

  UserSession({required this.userId, required this.user});

  factory UserSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return UserSession(
      userId: '${json['userId'] ?? user?['id'] ?? ''}',
      user: UserProfile.fromJson(
        user is Map<String, dynamic>
            ? user
            : {'id': json['userId'], 'name': 'Demo Kullanıcı', 'email': ''},
      ),
    );
  }
}

class UserProfile {
  final String id;
  final String name;
  final String email;
  final List<String> allergies;
  final String dietPreference;
  final int? calorieTarget;
  final List<String> favoriteCategories;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.allergies,
    required this.dietPreference,
    required this.calorieTarget,
    required this.favoriteCategories,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      email: '${json['email'] ?? ''}',
      allergies: _stringList(json['allergies']),
      dietPreference: '${json['dietPreference'] ?? ''}',
      calorieTarget: _asInt(json['calorieTarget']),
      favoriteCategories: _stringList(json['favoriteCategories']),
    );
  }
}

class Product {
  final String id;
  final String productName;
  final String normalizedName;
  final String restaurantName;
  final String restaurantRating;
  final String address;
  final String platform;
  final double? currentPrice;
  final double? originalPrice;
  final double discountAmount;
  final double discountPercent;
  final bool isSuspiciousDiscount;
  final String suspicionReason;
  final List<PriceAlternative> cheaperAlternatives;
  final String partnerUrl;
  final String description;
  final String category;
  final String productType;
  final String compareLabel;
  final bool isBestDeal;

  Product({
    required this.id,
    required this.productName,
    required this.normalizedName,
    required this.restaurantName,
    required this.restaurantRating,
    required this.address,
    required this.platform,
    required this.currentPrice,
    required this.originalPrice,
    required this.discountAmount,
    required this.discountPercent,
    required this.isSuspiciousDiscount,
    required this.suspicionReason,
    required this.cheaperAlternatives,
    required this.partnerUrl,
    required this.description,
    required this.category,
    required this.productType,
    required this.compareLabel,
    required this.isBestDeal,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: '${json['id'] ?? ''}',
      productName: '${json['productName'] ?? json['name'] ?? 'Ürün'}',
      normalizedName: '${json['normalizedName'] ?? ''}',
      restaurantName: '${json['restaurantName'] ?? 'Restoran'}',
      restaurantRating: '${json['restaurantRating'] ?? json['rating'] ?? '-'}',
      address: '${json['address'] ?? ''}',
      platform: '${json['platform'] ?? 'Partner'}',
      currentPrice: _asDouble(json['currentPrice'] ?? json['price']),
      originalPrice: _asDouble(json['originalPrice']),
      discountAmount: _asDouble(json['discountAmount']) ?? 0,
      discountPercent: _asDouble(json['discountPercent']) ?? 0,
      isSuspiciousDiscount: json['isSuspiciousDiscount'] == true,
      suspicionReason:
          '${json['suspicionReason'] ?? json['reason'] ?? 'Analiz bulunamadı.'}',
      cheaperAlternatives: (json['cheaperAlternatives'] is List)
          ? (json['cheaperAlternatives'] as List)
                .whereType<Map<String, dynamic>>()
                .map(PriceAlternative.fromJson)
                .toList()
          : [],
      partnerUrl: '${json['partnerUrl'] ?? ''}',
      description: '${json['description'] ?? ''}',
      category: '${json['category'] ?? 'Genel'}',
      productType: '${json['productType'] ?? 'yemek'}',
      compareLabel: '${json['compareLabel'] ?? ''}',
      isBestDeal: json['isBestDeal'] == true,
    );
  }
}

class PriceAlternative {
  final String id;
  final String productName;
  final String restaurantName;
  final String platform;
  final double? currentPrice;
  final double? originalPrice;
  final double discountPercent;
  final String partnerUrl;
  final String category;

  PriceAlternative({
    required this.id,
    required this.productName,
    required this.restaurantName,
    required this.platform,
    required this.currentPrice,
    required this.originalPrice,
    required this.discountPercent,
    required this.partnerUrl,
    required this.category,
  });

  factory PriceAlternative.fromJson(Map<String, dynamic> json) {
    return PriceAlternative(
      id: '${json['id'] ?? ''}',
      productName: '${json['productName'] ?? json['name'] ?? 'Ürün'}',
      restaurantName: '${json['restaurantName'] ?? 'Restoran'}',
      platform: '${json['platform'] ?? 'Partner'}',
      currentPrice: _asDouble(json['currentPrice'] ?? json['price']),
      originalPrice: _asDouble(json['originalPrice']),
      discountPercent: _asDouble(json['discountPercent']) ?? 0,
      partnerUrl: '${json['partnerUrl'] ?? ''}',
      category: '${json['category'] ?? 'Genel'}',
    );
  }
}

class PagedResult {
  final List<Product> items;
  final int total;
  final int page;
  final int totalPages;
  final int limit;

  PagedResult({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
    required this.limit,
  });

  bool get hasNextPage => page < totalPages;

  factory PagedResult.fromJson(dynamic json) {
    if (json is List) {
      // Eski format geriye dönük uyumluluk
      final products = json.whereType<Map<String, dynamic>>().map(Product.fromJson).toList();
      return PagedResult(
        items: products,
        total: products.length,
        page: 1,
        totalPages: 1,
        limit: products.length,
      );
    }
    final map = json as Map<String, dynamic>;
    return PagedResult(
      items: _productList(map['items']),
      total: _asInt(map['total']) ?? 0,
      page: _asInt(map['page']) ?? 1,
      totalPages: _asInt(map['totalPages']) ?? 1,
      limit: _asInt(map['limit']) ?? 20,
    );
  }
}

class CompareResult {
  final String query;
  final int count;
  final Product? bestDeal;
  final List<Product> suspicious;
  final List<Product> results;
  final String message;

  CompareResult({
    required this.query,
    required this.count,
    required this.bestDeal,
    required this.suspicious,
    required this.results,
    required this.message,
  });

  factory CompareResult.fromJson(Map<String, dynamic> json) {
    Product? bestDeal;
    if (json['bestDeal'] is Map<String, dynamic>) {
      bestDeal = Product.fromJson(json['bestDeal'] as Map<String, dynamic>);
    }
    return CompareResult(
      query: '${json['query'] ?? ''}',
      count: _asInt(json['count']) ?? 0,
      bestDeal: bestDeal,
      suspicious: _productList(json['suspicious']),
      results: _productList(json['results']),
      message: '${json['message'] ?? ''}',
    );
  }
}

double? _asDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  final text = value.toString().replaceAll('TL', '').replaceAll('₺', '').trim();
  return double.tryParse(text.replaceAll(',', '.'));
}

int? _asInt(dynamic value) {
  if (value == null || value == '') {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value.toString());
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return [];
}

List<Product> _productList(dynamic value) {
  if (value is! List) {
    return [];
  }
  return value.whereType<Map<String, dynamic>>().map(Product.fromJson).toList();
}

String formatPrice(dynamic value) {
  if (value == null) {
    return '-';
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '-';
    }
    if (trimmed.toLowerCase().contains('tl') || trimmed.contains('₺')) {
      return trimmed;
    }
    final parsed = _asDouble(trimmed);
    return parsed == null ? trimmed : '${parsed.toStringAsFixed(2)} TL';
  }
  if (value is num) {
    return '${value.toStringAsFixed(2)} TL';
  }
  return '$value';
}

String formatPercent(double value) {
  if (value <= 0) {
    return '%0';
  }
  return '%${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}';
}

String errorText(Object? error) {
  if (error == null) {
    return 'Beklenmeyen hata.';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

List<String> commaSeparated(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final api = ApiService();
  UserSession? session;
  LocationPrefs? locationPrefs;
  bool _locationLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final prefs = await LocationPrefs.load();
    if (mounted) {
      setState(() {
        locationPrefs = prefs;
        _locationLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locationLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Once login
    if (session == null) {
      return LoginRegisterPage(
        api: api,
        onAuthenticated: (value) => setState(() {
          session = value;
        }),
      );
    }

    // Login sonrasi konum secilmemisse konum secim ekrani
    if (locationPrefs == null) {
      return LocationSetupScreen(
        api: api,
        onLocationSelected: (prefs) {
          setState(() => locationPrefs = prefs);
        },
      );
    }

    return MainShell(
      api: api,
      session: session!,
      locationPrefs: locationPrefs!,
      onLogout: () => setState(() {
        session = null;
        locationPrefs = null; // cikista konumu sifirla
      }),
      onLocationChange: (prefs) => setState(() {
        locationPrefs = prefs;
      }),
      onSessionUpdate: (newSession) => setState(() {
        session = newSession;
      }),
    );
  }
}


// ─── GPS Normalize Yardımcısı ────────────────────────────────────────────────
String _normalizeForMatch(String value) {
  return value
      .toLowerCase()
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('i̇', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .trim();
}

// ─── LocationSetupScreen ─────────────────────────────────────────────────────
class LocationSetupScreen extends StatefulWidget {
  final ApiService api;
  final ValueChanged<LocationPrefs> onLocationSelected;

  const LocationSetupScreen({
    super.key,
    required this.api,
    required this.onLocationSelected,
  });

  @override
  State<LocationSetupScreen> createState() => _LocationSetupScreenState();
}

enum _LocationMode { detecting, detected, error, manual }

class _LocationSetupScreenState extends State<LocationSetupScreen>
    with SingleTickerProviderStateMixin {
  _LocationMode _mode = _LocationMode.detecting;

  // GPS ile bulunanlar
  CityModel? _gpsCity;
  DistrictModel? _gpsDistrict;
  bool _gpsDistrictLoading = false; // GPS'ten ilçe aranıyor
  String _gpsErrorMessage = '';

  // Manuel seçim
  List<CityModel> _cities = [];
  List<DistrictModel> _districts = [];
  CityModel? _selectedCity;
  DistrictModel? _selectedDistrict;
  bool _loadingCities = false;
  bool _loadingDistricts = false;
  bool _saving = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _detectGpsLocation();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Konum Tespiti (Backend IP → İstemci IP → GPS → Manuel) ──────────────
  //
  // Akış:
  //   0. Backend /api/geo-city → sunucu taraflı IP tespiti (en güvenilir)
  //   1. İstemci IP servisleri (ipapi.co, ipinfo.io) — fallback
  //   2. GPS → ilçeyi arka planda getir
  //   Hepsi başarısız olursa manuel seçime geçilir.

  Future<void> _detectGpsLocation() async {
    if (!mounted) return;
    setState(() => _mode = _LocationMode.detecting);

    // ── Yardımcı: İstemci IP'den şehir adını al ──────────────────────────
    Future<String?> tryIpGeoCity() async {
      // 1a. ipapi.co — region = il düzeyi
      try {
        final r = await http
            .get(Uri.parse('https://ipapi.co/json/'))
            .timeout(const Duration(seconds: 7));
        if (r.statusCode == 200) {
          final d = jsonDecode(r.body);
          if (d is Map<String, dynamic>) {
            final hasError = d['error'] == true ||
                (d['error'] is String && (d['error'] as String).isNotEmpty);
            if (!hasError) {
              final city = '${d['region'] ?? d['city'] ?? ''}';
              if (city.isNotEmpty) return city;
            }
          }
        }
      } catch (_) {}

      // 1b. ipinfo.io
      try {
        final r = await http
            .get(Uri.parse('https://ipinfo.io/json'))
            .timeout(const Duration(seconds: 7));
        if (r.statusCode == 200) {
          final d = jsonDecode(r.body);
          if (d is Map<String, dynamic>) {
            final city = '${d['region'] ?? d['city'] ?? ''}';
            if (city.isNotEmpty) return city;
          }
        }
      } catch (_) {}

      return null;
    }

    // ── Yardımcı: GPS'ten pozisyon al (izin varsa, yoksa null döner) ─────
    Future<Position?> tryGetPosition() async {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return null;

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return null;
        }

        Position? pos;
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {}

        pos ??= await Geolocator.getCurrentPosition(
          locationSettings: (!kIsWeb && Platform.isAndroid)
              ? AndroidSettings(
                  accuracy: LocationAccuracy.low,
                  forceLocationManager: false,
                )
              : const LocationSettings(accuracy: LocationAccuracy.low),
        ).timeout(const Duration(seconds: 12));

        return pos;
      } catch (_) {
        return null;
      }
    }

    // ── İlçe eşleştirme yardımcısı ───────────────────────────────────────
    Future<DistrictModel?> matchDistrictFromPos(
        Position pos, CityModel city) async {
      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isEmpty) return null;
        final place       = placemarks.first;
        final rawDistrict = place.subAdministrativeArea ?? place.locality ?? '';
        if (rawDistrict.isEmpty) return null;

        final districts = await widget.api.getDistricts(city.key);
        final norm      = _normalizeForMatch(rawDistrict);
        for (final d in districts) {
          if (_normalizeForMatch(d.key) == norm ||
              _normalizeForMatch(d.label) == norm) {
            return d;
          }
        }
        final partial = districts.firstWhere(
          (d) =>
              norm.contains(_normalizeForMatch(d.key)) ||
              _normalizeForMatch(d.key).contains(norm),
          orElse: () => DistrictModel(key: '', label: ''),
        );
        return partial.key.isEmpty ? null : partial;
      } catch (_) {
        return null;
      }
    }

    try {
      final gpsFuture = tryGetPosition(); // GPS paralel başlatılır

      // ── Aşama 0: Backend sunucu taraflı IP konum tespiti ─────────────────
      // Sunucu IP servislerine eriştiği için mobil cihaz kısıtlamalarından etkilenmez
      CityModel?    backendDetectedCity;
      DistrictModel? backendDetectedDistrict;
      try {
        final uri = Uri.parse('${widget.api.baseUrl}/geo-city');
        final r = await http.get(uri).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final d = jsonDecode(r.body);
          if (d is Map<String, dynamic>) {
            final cityKey   = '${d['city'] ?? ''}';
            final cityLabel = '${d['label'] ?? d['city'] ?? ''}';
            if (cityKey.isNotEmpty) {
              backendDetectedCity = CityModel(key: cityKey, label: cityLabel);
              // Backend ilçeyi de döndürdüyse kullan
              final distKey   = '${d['district'] ?? ''}';
              final distLabel = '${d['districtLabel'] ?? d['district'] ?? ''}';
              if (distKey.isNotEmpty) {
                backendDetectedDistrict = DistrictModel(key: distKey, label: distLabel);
              }
            }
          }
        }
      } catch (_) {}

      if (backendDetectedCity != null && mounted) {
        setState(() {
          _gpsCity              = backendDetectedCity;
          _gpsDistrict          = backendDetectedDistrict;
          _gpsDistrictLoading   = backendDetectedDistrict == null; // GPS arıyorsa loading
          _mode                 = _LocationMode.detected;
        });
        // İlçe bulunamadıysa GPS arka planda tamamlasın
        if (backendDetectedDistrict == null) {
          final detectedCity = backendDetectedCity!;
          gpsFuture.then((pos) async {
            if (pos == null || !mounted) {
              if (mounted) setState(() => _gpsDistrictLoading = false);
              return;
            }
            final district = await matchDistrictFromPos(pos, detectedCity);
            if (mounted) {
              setState(() {
                _gpsDistrict        = district;
                _gpsDistrictLoading = false;
              });
            }
          }).catchError((_) {
            if (mounted) setState(() => _gpsDistrictLoading = false);
          });
        }
        return;
      }

      // ── Aşama 1: İstemci tarafı IP servisleri ─────────────────────────
      final rawCity = await tryIpGeoCity();

      if (rawCity != null && rawCity.isNotEmpty) {
        final matchedCity = await _findCityMatch(rawCity);
        if (matchedCity != null && mounted) {
          setState(() {
            _gpsCity            = matchedCity;
            _gpsDistrict        = null;
            _gpsDistrictLoading = true; // GPS ile ilçe aranıyor
            _mode               = _LocationMode.detected;
          });

          // GPS ilçeyi arka planda getir
          gpsFuture.then((pos) async {
            if (pos == null || !mounted) {
              if (mounted) setState(() => _gpsDistrictLoading = false);
              return;
            }
            final district = await matchDistrictFromPos(pos, matchedCity);
            if (mounted) {
              setState(() {
                _gpsDistrict        = district;
                _gpsDistrictLoading = false;
              });
            }
          }).catchError((_) {
            if (mounted) setState(() => _gpsDistrictLoading = false);
          });

          return;
        }
      }

      // ── Aşama 2: GPS-only fallback ────────────────────────────────────────
      final position = await gpsFuture;
      if (position == null) {
        _setError('Konum alınamadı. Manuel seçim yapabilirsiniz.');
        return;
      }

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) {
        _setError('Adres bilgisi alınamadı. Manuel seçim yapabilirsiniz.');
        return;
      }

      final place       = placemarks.first;
      final rawCityGps  = place.administrativeArea ?? place.locality ?? '';
      final rawDistGps  = place.subAdministrativeArea ?? place.locality ?? '';

      final matchedCity = await _findCityMatch(rawCityGps);
      if (matchedCity == null) {
        _setError(
          '${rawCityGps.isNotEmpty ? '"$rawCityGps"' : 'Konumunuz'} veritabanında bulunamadı.\nManuel seçim yapabilirsiniz.',
        );
        return;
      }

      DistrictModel? matchedDistrict;
      if (rawDistGps.isNotEmpty) {
        try {
          final districts = await widget.api.getDistricts(matchedCity.key);
          final norm = _normalizeForMatch(rawDistGps);
          for (final d in districts) {
            if (_normalizeForMatch(d.key) == norm ||
                _normalizeForMatch(d.label) == norm) {
              matchedDistrict = d;
              break;
            }
          }
          matchedDistrict ??= districts.firstWhere(
            (d) =>
                norm.contains(_normalizeForMatch(d.key)) ||
                _normalizeForMatch(d.key).contains(norm),
            orElse: () => DistrictModel(key: '', label: ''),
          );
          if (matchedDistrict.key.isEmpty) matchedDistrict = null;
        } catch (_) {
          matchedDistrict = null;
        }
      }

      if (!mounted) return;
      setState(() {
        _gpsCity     = matchedCity;
        _gpsDistrict = matchedDistrict;
        _mode        = _LocationMode.detected;
      });
    } on TimeoutException {
      _setError('GPS sinyal alınamadı. Manuel seçim yapabilirsiniz.');
    } catch (e) {
      // ignore: avoid_print
      print('[Konum] Hata: $e');
      _setError('Konum alınamadı. Manuel seçim yapabilirsiniz.');
    }
  }

  // Şehir eşleştirme yardımcısı (tam + içerme kontrolü)
  Future<CityModel?> _findCityMatch(String rawCity) async {
    if (rawCity.isEmpty) return null;
    try {
      final cities = await widget.api.getCities();
      final norm = _normalizeForMatch(rawCity);
      for (final c in cities) {
        if (_normalizeForMatch(c.key) == norm ||
            _normalizeForMatch(c.label) == norm) {
          return c;
        }
      }
      for (final c in cities) {
        final ck = _normalizeForMatch(c.key);
        if (norm.contains(ck) || ck.contains(norm)) {
          return c;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }


  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _gpsErrorMessage = message;
      _mode = _LocationMode.error;
    });
    _loadCitiesForManual();
  }

  Future<void> _loadCitiesForManual() async {
    if (!mounted) return;
    setState(() => _loadingCities = true);
    try {
      final cities = await widget.api.getCities();
      if (mounted) setState(() { _cities = cities; _loadingCities = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  Future<void> _switchToManual() async {
    setState(() => _mode = _LocationMode.manual);
    if (_cities.isEmpty) _loadCitiesForManual();
  }

  Future<void> _selectCity(CityModel city) async {
    setState(() {
      _selectedCity = city;
      _selectedDistrict = null;
      _districts = [];
      _loadingDistricts = true;
    });
    try {
      final districts = await widget.api.getDistricts(city.key);
      if (mounted) setState(() { _districts = districts; _loadingDistricts = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingDistricts = false);
    }
  }

  Future<void> _confirm({CityModel? city, DistrictModel? district}) async {
    final c = city ?? _selectedCity;
    if (c == null) return;
    setState(() => _saving = true);
    final prefs = LocationPrefs(
      city: c.key,
      district: district?.key ?? _selectedDistrict?.key ?? '',
      cityLabel: c.label,
      districtLabel: district?.label ?? _selectedDistrict?.label ?? '',
    );
    await prefs.save();
    if (mounted) widget.onLocationSelected(prefs);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryOrange.withValues(alpha: 0.08),
              const Color(0xfff5f5f5),
            ],
          ),
        ),
        child: SafeArea(
          child: switch (_mode) {
            _LocationMode.detecting => _buildDetecting(),
            _LocationMode.detected  => _buildDetected(),
            _LocationMode.error     => _buildManualWithError(showError: true),
            _LocationMode.manual    => _buildManualWithError(showError: false),
          },
        ),
      ),
    );
  }

  // ── Detecting ────────────────────────────────────────────────────────────

  Widget _buildDetecting() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.my_location_rounded,
                  size: 48,
                  color: AppColors.primaryOrange,
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Konumunuz tespit ediliyor…',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Bulunduğunuz şehir ve ilçeyi otomatik olarak buluyoruz.',
              style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
            const SizedBox(height: 28),
            TextButton.icon(
              onPressed: _switchToManual,
              icon: const Icon(Icons.list_alt_rounded, size: 18),
              label: const Text('Elle Seç'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black45,
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Detected ─────────────────────────────────────────────────────────────

  Widget _buildDetected() {
    final city = _gpsCity!;
    final district = _gpsDistrict;
    final label = district != null
        ? '${district.label}, ${city.label}'
        : city.label;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primaryOrange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.location_on, size: 48, color: AppColors.primaryOrange),
          ),
          const SizedBox(height: 24),
          const Text(
            'Konumunuz Bulundu',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Sadece sizin bölgenizdeki\nrestoranları ve fırsatları göstereceğiz.',
            style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // Konum kartı
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryOrange.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.place, color: AppColors.primaryOrange, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_gpsDistrictLoading)
                        Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryOrange,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'İlçe belirleniyor…',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.primaryOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      else if (district != null)
                        Text(
                          district.label,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      Text(
                        city.label,
                        style: TextStyle(
                          fontSize: district != null ? 14 : 20,
                          fontWeight: district != null
                              ? FontWeight.w500
                              : FontWeight.w900,
                          color: district != null
                              ? Colors.black54
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.check_circle, color: Colors.green.shade500, size: 28),
              ],
            ),
          ),
          const Spacer(),
          // Devam et butonu
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: _saving ? null : () => _confirm(city: city, district: district),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      '$label ile Devam Et →',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          // İlçe seç / değiştir + Elle seç
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (!_gpsDistrictLoading)
                TextButton.icon(
                  onPressed: () async {
                    // İlçe listesini yükle ve bottom sheet göster
                    if (_districts.isEmpty && _gpsCity != null) {
                      setState(() => _loadingDistricts = true);
                      try {
                        final list = await widget.api.getDistricts(_gpsCity!.key);
                        if (mounted) setState(() { _districts = list; _loadingDistricts = false; });
                      } catch (_) {
                        if (mounted) setState(() => _loadingDistricts = false);
                      }
                    }
                    if (!mounted) return;
                    final picked = await showModalBottomSheet<DistrictModel>(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 12),
                            Container(
                              width: 40, height: 4,
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'İlçe Seçin',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            if (_loadingDistricts)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              )
                            else
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 320),
                                child: ListView(
                                  shrinkWrap: true,
                                  children: _districts.map((d) => ListTile(
                                    title: Text(d.label),
                                    trailing: _gpsDistrict?.key == d.key
                                        ? const Icon(Icons.check, color: Colors.green)
                                        : null,
                                    onTap: () => Navigator.pop(context, d),
                                  )).toList(),
                                ),
                              ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    );
                    if (picked != null && mounted) {
                      setState(() => _gpsDistrict = picked);
                    }
                  },
                  icon: Icon(
                    _gpsDistrict != null ? Icons.edit_location_alt_rounded : Icons.add_location_alt_rounded,
                    size: 18,
                    color: AppColors.primaryOrange,
                  ),
                  label: Text(
                    _gpsDistrict != null ? 'İlçeyi Değiştir' : 'İlçe Seç',
                    style: TextStyle(
                      color: AppColors.primaryOrange,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryOrange,
                  ),
                ),
              TextButton(
                onPressed: _switchToManual,
                child: Text(
                  'Elle seç',
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Manual / Error ───────────────────────────────────────────────────────

  Widget _buildManualWithError({required bool showError}) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.location_on, size: 48, color: AppColors.primaryOrange),
              ),
              const SizedBox(height: 20),
              Text(
                showError ? 'Konum Tespit Edilemedi' : 'Konumunuzu Seçin',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (showError && _gpsErrorMessage.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    _gpsErrorMessage,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange.shade800,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Text(
                  'Sadece sizin bölgenizdeki restoranları\nve fırsatları göstereceğiz.',
                  style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              // Tekrar dene butonu
              if (showError) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _detectGpsLocation,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tekrar Dene'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primaryOrange),
                    foregroundColor: AppColors.primaryOrange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Şehir/ilçe chip'leri
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Şehir', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                if (_loadingCities)
                  const Center(child: CircularProgressIndicator())
                else
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _cities.map((city) => ChoiceChip(
                        label: Text(city.label),
                        selected: _selectedCity?.key == city.key,
                        showCheckmark: false,
                        selectedColor: AppColors.primaryOrange,
                        labelStyle: TextStyle(
                          color: _selectedCity?.key == city.key ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        onSelected: (_) => _selectCity(city),
                      )).toList(),
                    ),
                  ),

                if (_selectedCity != null) ...[
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Text('İlçe', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(width: 8),
                      const Text('(isteğe bağlı)', style: TextStyle(color: Colors.black45, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_loadingDistricts)
                    const Center(child: CircularProgressIndicator())
                  else
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Tüm İlçeler'),
                            selected: _selectedDistrict == null,
                            showCheckmark: false,
                            selectedColor: Colors.grey.shade600,
                            labelStyle: TextStyle(
                              color: _selectedDistrict == null ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => setState(() => _selectedDistrict = null),
                          ),
                          ..._districts.map((d) => ChoiceChip(
                            label: Text(d.label),
                            selected: _selectedDistrict?.key == d.key,
                            showCheckmark: false,
                            selectedColor: AppColors.primaryOrange,
                            labelStyle: TextStyle(
                              color: _selectedDistrict?.key == d.key ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => setState(() => _selectedDistrict = d),
                          )),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        // Onayla butonu
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: _selectedCity == null || _saving ? null : _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      _selectedCity == null
                          ? 'Şehir seçin'
                          : _selectedDistrict != null
                              ? '${_selectedDistrict!.label}, ${_selectedCity!.label} →'
                              : '${_selectedCity!.label} →',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}



class LoginRegisterPage extends StatefulWidget {
  final ApiService api;
  final ValueChanged<UserSession> onAuthenticated;

  const LoginRegisterPage({
    super.key,
    required this.api,
    required this.onAuthenticated,
  });

  @override
  State<LoginRegisterPage> createState() => _LoginRegisterPageState();
}

class _LoginRegisterPageState extends State<LoginRegisterPage> {
  final nameController = TextEditingController(text: 'Demo Kullanıcı');
  final emailController = TextEditingController(text: 'demo@neyesem.local');
  final passwordController = TextEditingController(text: '123456');
  bool isRegister = false;
  bool isLoading = false;
  String? errorMessage;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final session = isRegister
          ? await widget.api.register(
              name: nameController.text.trim(),
              email: emailController.text.trim(),
              password: passwordController.text,
            )
          : await widget.api.login(
              email: emailController.text.trim(),
              password: passwordController.text,
            );
      if (!mounted) {
        return;
      }
      widget.onAuthenticated(session);
    } catch (error) {
      setState(() => errorMessage = errorText(error));
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.restaurant_menu,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'NeYesem',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Fiyatları karşılaştır, sahte indirimleri yakala.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Giriş')),
                      ButtonSegment(value: true, label: Text('Kayıt')),
                    ],
                    selected: {isRegister},
                    onSelectionChanged: (value) =>
                        setState(() => isRegister = value.first),
                  ),
                  const SizedBox(height: 16),
                  if (isRegister) ...[
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Ad Soyad',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    MessageBox(
                      text: errorMessage!,
                      icon: Icons.error_outline,
                      color: Colors.red,
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isLoading ? null : submit,
                      icon: isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              isRegister ? Icons.person_add_alt : Icons.login,
                            ),
                      label: Text(isRegister ? 'Kayıt ol' : 'Giriş yap'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final ApiService api;
  final UserSession session;
  final LocationPrefs locationPrefs;
  final VoidCallback onLogout;
  final ValueChanged<LocationPrefs> onLocationChange;
  final ValueChanged<UserSession> onSessionUpdate;

  const MainShell({
    super.key,
    required this.api,
    required this.session,
    required this.locationPrefs,
    required this.onLogout,
    required this.onLocationChange,
    required this.onSessionUpdate,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int selectedIndex = 0;

  void _changeLocation() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LocationSetupScreen(
        api: widget.api,
        onLocationSelected: (prefs) {
          Navigator.pop(context);
          widget.onLocationChange(prefs);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.locationPrefs;
    final locationLabel = loc.displayLabel;

    final pages = [
      HomeTab(api: widget.api, city: loc.city, district: loc.district, allergies: widget.session.user.allergies),
      CompareTab(api: widget.api, city: loc.city, district: loc.district, allergies: widget.session.user.allergies),
      SuspiciousDiscountTab(api: widget.api, city: loc.city, district: loc.district, allergies: widget.session.user.allergies),
      ProfileTab(
        api: widget.api,
        session: widget.session,
        onLogout: widget.onLogout,
        onSessionUpdate: widget.onSessionUpdate,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Konum bandı
          InkWell(
            onTap: _changeLocation,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.primaryOrange.withValues(alpha: 0.08),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_on, size: 14, color: AppColors.primaryOrange),
                  const SizedBox(width: 4),
                  Text(
                    locationLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryOrange),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 12, color: AppColors.primaryOrange),
                ],
              ),
            ),
          ),
          NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => setState(() => selectedIndex = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Ana Sayfa',
              ),
              NavigationDestination(
                icon: Icon(Icons.compare_arrows),
                label: 'Karşılaştır',
              ),
              NavigationDestination(
                icon: Icon(Icons.warning_amber_outlined),
                selectedIcon: Icon(Icons.warning),
                label: 'Sahte İndirim',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profil',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Sıralama seçenekleri
enum SortOption {
  recommended('', 'Önerilen'),
  priceAsc('price_asc', 'En Ucuz'),
  priceDesc('price_desc', 'En Pahalı'),
  discount('discount', 'En Yüksek İndirim');

  final String value;
  final String label;
  const SortOption(this.value, this.label);
}

class HomeTab extends StatefulWidget {
  final ApiService api;
  final String city;
  final String district;
  final List<String> allergies;

  const HomeTab({super.key, required this.api, this.city = '', this.district = '', this.allergies = const []});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final searchController = TextEditingController();
  final scrollController = ScrollController();
  String _searchQuery = '';
  SortOption _sortOption = SortOption.recommended;

  // Pagination state
  final List<Product> _products = [];
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPage(1, replace: true);
    scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.city != widget.city || oldWidget.district != widget.district) {
      // Şehir veya ilçe değişti, veriyi yeniden yükle
      _products.clear();
      _currentPage = 1;
      _loadPage(1, replace: true);
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadPage(int page, {bool replace = false}) async {
    if (_isLoading || _isLoadingMore) return;
    setState(() {
      if (replace) {
        _isLoading = true;
        _errorMessage = null;
      } else {
        _isLoadingMore = true;
      }
    });
    try {
      final PagedResult result;
      if (_searchQuery.isNotEmpty) {
        result = await widget.api.searchProducts(
          _searchQuery,
          page: page,
          limit: 20,
          sort: _sortOption.value,
          city: widget.city,
          district: widget.district,
        );
      } else {
        result = await widget.api.getDeals(
          page: page,
          limit: 20,
          sort: _sortOption.value,
          city: widget.city,
          district: widget.district,
        );
      }
      if (!mounted) return;
      setState(() {
        if (replace) {
          _products.clear();
        }
        _products.addAll(result.items);
        _currentPage = result.page;
        _totalPages = result.totalPages;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;
    await _loadPage(_currentPage + 1);
  }

  void _onSearch() {
    setState(() {
      _searchQuery = searchController.text.trim();
      _products.clear();
      _currentPage = 1;
    });
    _loadPage(1, replace: true);
  }

  void _onSortChanged(SortOption? option) {
    if (option == null || option == _sortOption) return;
    setState(() {
      _sortOption = option;
      _products.clear();
      _currentPage = 1;
    });
    _loadPage(1, replace: true);
  }

  Future<void> _refresh() async {
    setState(() {
      _products.clear();
      _currentPage = 1;
    });
    await _loadPage(1, replace: true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Text(
              'Bugün ne yesem?',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Gerçek avantajlı ürünler, sahte indirimleri yakala.',
              style: TextStyle(color: Colors.black54),
            ),
          ),

          // Arama çubuğu
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _onSearch(),
                    decoration: InputDecoration(
                      hintText: 'Ürün, restoran ara...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                _searchQuery = '';
                                _onSearch();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _onSearch,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  child: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ),

          // Sıralama satırı
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.sort, size: 18, color: Colors.black54),
                const SizedBox(width: 6),
                const Text('Sırala:',
                    style: TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: SortOption.values.map((opt) {
                        final isSelected = opt == _sortOption;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(opt.label),
                            selected: isSelected,
                            showCheckmark: false,
                            selectedColor: AppColors.primaryOrange,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            onSelected: (_) => _onSortChanged(opt),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Ürün listesi
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null && _products.isEmpty
                    ? EmptyState(
                        icon: Icons.cloud_off_outlined,
                        text: _errorMessage!,
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _products.length +
                              (_isLoadingMore ? 1 : 0) +
                              1,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return SectionHeader(
                                title: _searchQuery.isNotEmpty
                                    ? '"$_searchQuery" için sonuçlar'
                                    : 'En avantajlı ürünler',
                                icon: _searchQuery.isNotEmpty
                                    ? Icons.search
                                    : Icons.local_offer_outlined,
                                color: Colors.green,
                              );
                            }
                            final dataIndex = index - 1;
                            if (dataIndex >= _products.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                    child: CircularProgressIndicator()),
                              );
                            }
                            final product = _products[dataIndex];
                            return ProductCard(
                              product: product,
                              accentColor: Colors.green,
                              badgeText: 'Gerçek avantaj',
                              onTap: () => openProductDetail(
                                  context, widget.api, product,
                                  allergies: widget.allergies),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class CompareTab extends StatefulWidget {
  final ApiService api;
  final String city;
  final String district;
  final List<String> allergies;

  const CompareTab({super.key, required this.api, this.city = '', this.district = '', this.allergies = const []});

  @override
  State<CompareTab> createState() => _CompareTabState();
}

class _CompareTabState extends State<CompareTab> {
  final queryController = TextEditingController(text: 'tavuk');
  Future<CompareResult>? future;
  bool _locationChanged = false;

  @override
  void initState() {
    super.initState();
    // Ilk yuklemede otomatik ara
    future = widget.api.compare(queryController.text.trim(), city: widget.city, district: widget.district);
  }

  @override
  void didUpdateWidget(CompareTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.city != widget.city || oldWidget.district != widget.district) {
      // Konum degisti - sadece flag set et, otomatik sorgu YAPMA
      setState(() {
        _locationChanged = true;
        future = null;
      });
    }
  }

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  void search() {
    final query = queryController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Karşılaştırmak için ürün adı yazın.')),
      );
      return;
    }
    setState(() {
      _locationChanged = false;
      future = widget.api.compare(query, city: widget.city, district: widget.district);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      title: 'Karşılaştır',
      subtitle: 'Burger, tavuk, pizza veya pestil arayarak fiyatları sırala.',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: queryController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => search(),
                    decoration: const InputDecoration(
                      hintText: 'tavuk, burger, pizza, pestil',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: search,
                  child: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ),
          // Konum degisince bilgi mesaji goster
          if (_locationChanged)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: AppColors.primaryOrange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Konum değişti. Yeni konum için aramak üzere butona basın.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: FutureBuilder<CompareResult>(
              future: future,
              builder: (context, snapshot) {
                return DataState<CompareResult>(
                  snapshot: snapshot,
                  emptyText: 'Karşılaştırma için ürün adı yazın.',
                  builder: (result) {
                    if (result.results.isEmpty) {
                      return EmptyState(
                        icon: Icons.search_off,
                        text: result.message.isNotEmpty
                            ? result.message
                            : 'Bu arama için ürün bulunamadı.',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: result.results.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return SectionHeader(
                            title:
                                '${result.count} sonuç fiyatına göre sıralandı',
                            icon: Icons.price_check,
                            color: Colors.deepOrange,
                          );
                        }
                        final product = result.results[index - 1];
                        final isWarning =
                            product.compareLabel.contains('Sahte') ||
                            product.isSuspiciousDiscount;
                        return ProductCard(
                          product: product,
                          accentColor: product.isBestDeal
                              ? Colors.green
                              : isWarning
                              ? Colors.red
                              : Colors.deepOrange,
                          badgeText: product.compareLabel.isNotEmpty
                              ? product.compareLabel
                              : product.isBestDeal
                              ? 'En iyi fiyat'
                              : 'Daha pahalı',
                          onTap: () =>
                              openProductDetail(context, widget.api, product,
                                  allergies: widget.allergies),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SuspiciousDiscountTab extends StatefulWidget {
  final ApiService api;
  final String city;
  final String district;
  final List<String> allergies;

  const SuspiciousDiscountTab({super.key, required this.api, this.city = '', this.district = '', this.allergies = const []});

  @override
  State<SuspiciousDiscountTab> createState() => _SuspiciousDiscountTabState();
}

class _SuspiciousDiscountTabState extends State<SuspiciousDiscountTab> {
  late Future<List<Product>> future;

  @override
  void initState() {
    super.initState();
    future = widget.api.getSuspiciousDiscounts(city: widget.city, district: widget.district);
  }

  @override
  void didUpdateWidget(SuspiciousDiscountTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.city != widget.city || oldWidget.district != widget.district) {
      setState(() {
        future = widget.api.getSuspiciousDiscounts(city: widget.city, district: widget.district);
      });
    }
  }

  Future<void> refresh() async {
    setState(() {
      future = widget.api.getSuspiciousDiscounts(city: widget.city, district: widget.district);    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      title: 'Sahte indirimler',
      subtitle: 'Benzer ürünlere göre pahalı kalan indirimleri yakala.',
      child: FutureBuilder<List<Product>>(
        future: future,
        builder: (context, snapshot) {
          return DataState<List<Product>>(
            snapshot: snapshot,
            emptyText: 'Şüpheli indirim bulunamadı.',
            builder: (products) {
              return RefreshIndicator(
                onRefresh: refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: products.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return const SectionHeader(
                        title: 'Uyarı listesi',
                        icon: Icons.warning_amber_outlined,
                        color: Colors.red,
                      );
                    }
                    final product = products[index - 1];
                    return ProductCard(
                      product: product,
                      accentColor: Colors.red,
                      badgeText: 'Sahte indirim şüphesi',
                      showSuspicion: true,
                      onTap: () =>
                          openProductDetail(context, widget.api, product,
                              allergies: widget.allergies),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ProfileTab extends StatefulWidget {
  final ApiService api;
  final UserSession session;
  final VoidCallback onLogout;
  final ValueChanged<UserSession> onSessionUpdate;

  const ProfileTab({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
    required this.onSessionUpdate,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late Future<UserProfile> future;
  final nameController = TextEditingController();
  final allergiesController = TextEditingController();
  final dietController = TextEditingController();
  final calorieController = TextEditingController();
  final categoriesController = TextEditingController();
  bool isSaving = false;
  bool controllersFilled = false;

  @override
  void initState() {
    super.initState();
    future = widget.api.getProfile(widget.session.userId);
  }

  @override
  void dispose() {
    nameController.dispose();
    allergiesController.dispose();
    dietController.dispose();
    calorieController.dispose();
    categoriesController.dispose();
    super.dispose();
  }

  void fillControllers(UserProfile profile) {
    if (controllersFilled) {
      return;
    }
    controllersFilled = true;
    nameController.text = profile.name;
    allergiesController.text = profile.allergies.join(', ');
    dietController.text = profile.dietPreference;
    calorieController.text = profile.calorieTarget?.toString() ?? '';
    categoriesController.text = profile.favoriteCategories.join(', ');
  }

  Future<void> save() async {
    setState(() => isSaving = true);
    try {
      final updated = await widget.api.updateProfile(
        widget.session.userId,
        name: nameController.text.trim(),
        allergies: commaSeparated(allergiesController.text),
        dietPreference: dietController.text.trim(),
        calorieTarget: int.tryParse(calorieController.text.trim()),
        favoriteCategories: commaSeparated(categoriesController.text),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        controllersFilled = false;
        future = Future.value(updated);
      });
      widget.onSessionUpdate(UserSession(userId: widget.session.userId, user: updated));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil bilgileri kaydedildi.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorText(error))));
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      title: 'Profil',
      subtitle: 'Alerjen, diyet ve kalori hedefini demo backend’e kaydet.',
      trailing: IconButton(
        tooltip: 'Çıkış yap',
        onPressed: widget.onLogout,
        icon: const Icon(Icons.logout),
      ),
      child: FutureBuilder<UserProfile>(
        future: future,
        builder: (context, snapshot) {
          return DataState<UserProfile>(
            snapshot: snapshot,
            emptyText: 'Profil bilgisi bulunamadı.',
            builder: (profile) {
              fillControllers(profile);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  DemoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.email,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Ad',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: allergiesController,
                          decoration: const InputDecoration(
                            labelText: 'Alerjenler',
                            hintText: 'fıstık, gluten',
                            prefixIcon: Icon(Icons.health_and_safety_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: dietController,
                          decoration: const InputDecoration(
                            labelText: 'Diyet tercihi',
                            hintText: 'Dengeli, vegan, yüksek protein',
                            prefixIcon: Icon(Icons.eco_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: calorieController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Kalori hedefi',
                            hintText: '2200',
                            prefixIcon: Icon(
                              Icons.local_fire_department_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: categoriesController,
                          decoration: const InputDecoration(
                            labelText: 'Favori kategoriler',
                            hintText: 'tavuk, burger, pizza',
                            prefixIcon: Icon(Icons.favorite_border),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: isSaving ? null : save,
                            icon: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('Kaydet'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class ProductDetailPage extends StatefulWidget {
  final ApiService api;
  final Product product;
  final List<String> allergies;

  const ProductDetailPage({
    super.key,
    required this.api,
    required this.product,
    this.allergies = const [],
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late Future<Product> future;

  /// Kullanıcının alerjen listesini (virgülle veya boşlukla ayrılmış string listesi)
  /// ürünün adı+açıklaması+kategorisiyle eşleştirir. Eşleşen alerjen token'larını döner.
  List<String> _detectAllergens(Product product, List<String> rawAllergies) {
    if (rawAllergies.isEmpty) return [];
    // Virgülle ve boşlukla ayrılmış tek girişleri de destekle
    final tokens = rawAllergies
        .expand((a) => a.split(RegExp(r'[,;]')))
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return [];

    // Ürün metnini birleştir
    final haystack = '${product.productName} ${product.description} ${product.category}'
        .toLowerCase()
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i');

    // Popüler Türkçe alerjen eş anlamlıları
    const synonyms = {
      'gluten': ['gluten', 'glulen', 'glutin', 'bugday', 'arpa', 'cavdar', 'yulaf', 'un'],
      'glüten': ['gluten', 'glutin'],
      'süt': ['sut', 'peynir', 'tereyag', 'krem', 'yogurt', 'krema', 'laktoz', 'dairy'],
      'yumurta': ['yumurta', 'egg'],
      'fıstık': ['fistik', 'yer fistik', 'yerfistigi', 'peanut', 'fistigi'],
      'fındık': ['findik', 'hazelnut', 'findigi'],
      'ceviz': ['ceviz', 'walnut', 'pecan', 'pikan'],
      'badem': ['badem', 'almond'],
      'soya': ['soya', 'soy'],
      'susam': ['susam', 'tahin', 'sesame'],
      'hardal': ['hardal', 'mustard'],
      'kabuklu deniz ürünleri': ['karides', 'istakoz', 'yenges', 'shellfish', 'shrimp'],
      'balık': ['balik', 'somon', 'ton baligi', 'fish'],
      'kereviz': ['kereviz', 'celery'],
    };

    final matched = <String>[];
    for (final token in tokens) {
      final normalToken = token
          .replaceAll('ü', 'u')
          .replaceAll('ö', 'o')
          .replaceAll('ç', 'c')
          .replaceAll('ş', 's')
          .replaceAll('ğ', 'g')
          .replaceAll('ı', 'i');

      // Doğrudan eşleşme
      if (haystack.contains(normalToken)) {
        matched.add(token);
        continue;
      }

      // Eş anlamlı eşleşme
      final syns = synonyms[token] ?? synonyms[normalToken];
      if (syns != null) {
        if (syns.any((s) => haystack.contains(s))) {
          matched.add(token);
        }
      }
    }
    return matched;
  }


  @override
  void initState() {
    super.initState();
    future = widget.api.getProductAnalysis(widget.product.id, widget.product);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ürün Detayı')),
      body: FutureBuilder<Product>(
        future: future,
        builder: (context, snapshot) {
          final product = snapshot.data ?? widget.product;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DemoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.productName,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${product.restaurantName} • ${product.platform}',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        StatusBadge(
                          text: product.isSuspiciousDiscount
                              ? 'Şüpheli'
                              : 'Avantaj',
                          color: product.isSuspiciousDiscount
                              ? Colors.red
                              : Colors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    PriceGrid(product: product),
                    const SizedBox(height: 18),
                    MessageBox(
                      text: product.suspicionReason,
                      icon: product.isSuspiciousDiscount
                          ? Icons.warning_amber_outlined
                          : Icons.verified_outlined,
                      color: product.isSuspiciousDiscount
                          ? Colors.red
                          : Colors.green,
                    ),
                    // ─── Alerjen Uyarısı ────────────────────────────────────
                    Builder(builder: (_) {
                      final matched = _detectAllergens(
                        product,
                        widget.allergies,
                      );
                      if (matched.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.no_food, color: Colors.deepOrange, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Alerjen Uyarısı',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.deepOrange,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Bu ürün profilinizdeki alerjenlerden bazılarını içerebilir: ${matched.join(', ')}. Sipariş vermeden önce lütfen ürün içeriğini kontrol ediniz.',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.deepOrange,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (product.description.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(product.description),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => launchPartnerUrl(context, product),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Partner uygulamada görüntüle'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (snapshot.hasError)
                MessageBox(
                  text: 'Analiz yenilenemedi, listedeki veri gösteriliyor.',
                  icon: Icons.info_outline,
                  color: Colors.orange,
                ),
              if (product.cheaperAlternatives.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionHeader(
                  title: 'Daha ucuz alternatifler',
                  icon: Icons.south_east,
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                ...product.cheaperAlternatives.map(
                  (alternative) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AlternativeCard(alternative: alternative),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

void openProductDetail(
  BuildContext context,
  ApiService api,
  Product product, {
  List<String> allergies = const [],
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProductDetailPage(
        api: api,
        product: product,
        allergies: allergies,
      ),
    ),
  );
}

class AppScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const AppScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class DataState<T> extends StatelessWidget {
  final AsyncSnapshot<T> snapshot;
  final String emptyText;
  final Widget Function(T data) builder;

  const DataState({
    super.key,
    required this.snapshot,
    required this.emptyText,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        text: errorText(snapshot.error),
      );
    }

    final data = snapshot.data;
    if (data == null) {
      return EmptyState(icon: Icons.inbox_outlined, text: emptyText);
    }
    if (data is List && data.isEmpty) {
      return EmptyState(icon: Icons.inbox_outlined, text: emptyText);
    }

    return builder(data);
  }
}

class ProductCard extends StatelessWidget {
  final Product product;
  final Color accentColor;
  final String badgeText;
  final VoidCallback onTap;
  final bool showSuspicion;

  const ProductCard({
    super.key,
    required this.product,
    required this.accentColor,
    required this.badgeText,
    required this.onTap,
    this.showSuspicion = false,
  });

  @override
  Widget build(BuildContext context) {
    return DemoCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${product.restaurantName} • ${product.platform}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatPrice(product.currentPrice),
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (product.originalPrice != null &&
                      product.originalPrice != product.currentPrice)
                    Text(
                      formatPrice(product.originalPrice),
                      style: const TextStyle(
                        color: Colors.black45,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(text: badgeText, color: accentColor),
              if (product.discountPercent > 0)
                StatusBadge(
                  text: '${formatPercent(product.discountPercent)} indirim',
                  color: Colors.deepOrange,
                ),
              StatusBadge(text: product.category, color: Colors.blueGrey),
            ],
          ),
          if (showSuspicion || product.cheaperAlternatives.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              product.suspicionReason,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: product.isSuspiciousDiscount
                    ? Colors.red.shade700
                    : Colors.black54,
              ),
            ),
          ],
          if (product.cheaperAlternatives.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Daha ucuz alternatif: ${product.cheaperAlternatives.first.restaurantName} • ${formatPrice(product.cheaperAlternatives.first.currentPrice)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

class AlternativeCard extends StatelessWidget {
  final PriceAlternative alternative;

  const AlternativeCard({super.key, required this.alternative});

  @override
  Widget build(BuildContext context) {
    return DemoCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.trending_down, color: Colors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alternative.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${alternative.restaurantName} • ${alternative.platform}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatPrice(alternative.currentPrice),
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class PriceGrid extends StatelessWidget {
  final Product product;

  const PriceGrid({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 520;
        final children = [
          PriceMetric(
            label: 'Güncel fiyat',
            value: formatPrice(product.currentPrice),
            color: Colors.deepOrange,
          ),
          PriceMetric(
            label: 'İndirimsiz',
            value: formatPrice(product.originalPrice),
            color: Colors.black87,
          ),
          PriceMetric(
            label: 'İndirim',
            value: formatPercent(product.discountPercent),
            color: Colors.green,
          ),
          PriceMetric(
            label: 'Durum',
            value: product.isSuspiciousDiscount ? 'Şüpheli' : 'Makul',
            color: product.isSuspiciousDiscount ? Colors.red : Colors.green,
          ),
        ];

        return GridView.count(
          crossAxisCount: isWide ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: isWide ? 1.7 : 1.55,
          children: children,
        );
      },
    );
  }
}

class PriceMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const PriceMetric({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DemoCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const DemoCard({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const StatusBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ProductTypeFilter kaldırıldı - arama + sıralama sistemi ile değiştirildi

class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class MessageBox extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const MessageBox({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withValues(alpha: 0.95),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const EmptyState({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.black38),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
