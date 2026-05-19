import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api',
);

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
  ApiService({this.baseUrl = apiBaseUrl});

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

  Future<List<Product>> getDeals() async {
    final data = await _request('/deals');
    return _parseProducts(data);
  }

  Future<List<Product>> getSuspiciousDiscounts() async {
    final data = await _request('/suspicious-discounts');
    return _parseProducts(data);
  }

  Future<CompareResult> compare(String query) async {
    final data = await _request('/compare', queryParameters: {'query': query});
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

  @override
  Widget build(BuildContext context) {
    if (session == null) {
      return LoginRegisterPage(
        api: api,
        onAuthenticated: (value) => setState(() {
          session = value;
        }),
      );
    }
    return MainShell(
      api: api,
      session: session!,
      onLogout: () => setState(() {
        session = null;
      }),
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
  final VoidCallback onLogout;

  const MainShell({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(api: widget.api),
      CompareTab(api: widget.api),
      SuspiciousDiscountTab(api: widget.api),
      ProfileTab(
        api: widget.api,
        session: widget.session,
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
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
    );
  }
}

class HomeTab extends StatefulWidget {
  final ApiService api;

  const HomeTab({super.key, required this.api});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<List<Product>> future;

  @override
  void initState() {
    super.initState();
    future = widget.api.getDeals();
  }

  Future<void> refresh() async {
    setState(() {
      future = widget.api.getDeals();
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      title: 'Bugün ne yesem?',
      subtitle: 'Fiyatları karşılaştır, sahte indirimleri yakala.',
      child: FutureBuilder<List<Product>>(
        future: future,
        builder: (context, snapshot) {
          return DataState<List<Product>>(
            snapshot: snapshot,
            emptyText:
                'Avantajlı ürün bulunamadı. Backend verisini kontrol edin.',
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
                        title: 'En avantajlı ürünler',
                        icon: Icons.local_offer_outlined,
                        color: Colors.green,
                      );
                    }
                    final product = products[index - 1];
                    return ProductCard(
                      product: product,
                      accentColor: Colors.green,
                      badgeText: 'Gerçek avantaj',
                      onTap: () =>
                          openProductDetail(context, widget.api, product),
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

class CompareTab extends StatefulWidget {
  final ApiService api;

  const CompareTab({super.key, required this.api});

  @override
  State<CompareTab> createState() => _CompareTabState();
}

class _CompareTabState extends State<CompareTab> {
  final queryController = TextEditingController(text: 'tavuk');
  Future<CompareResult>? future;

  @override
  void initState() {
    super.initState();
    future = widget.api.compare(queryController.text.trim());
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
      future = widget.api.compare(query);
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
                              openProductDetail(context, widget.api, product),
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

  const SuspiciousDiscountTab({super.key, required this.api});

  @override
  State<SuspiciousDiscountTab> createState() => _SuspiciousDiscountTabState();
}

class _SuspiciousDiscountTabState extends State<SuspiciousDiscountTab> {
  late Future<List<Product>> future;

  @override
  void initState() {
    super.initState();
    future = widget.api.getSuspiciousDiscounts();
  }

  Future<void> refresh() async {
    setState(() {
      future = widget.api.getSuspiciousDiscounts();
    });
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
                          openProductDetail(context, widget.api, product),
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

  const ProfileTab({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil backend/data/users.json içine kaydedildi.'),
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

  const ProductDetailPage({
    super.key,
    required this.api,
    required this.product,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late Future<Product> future;

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

void openProductDetail(BuildContext context, ApiService api, Product product) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProductDetailPage(api: api, product: product),
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
