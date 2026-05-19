class UserModel {
  final String id;
  final String email;
  final String phone;
  final String oauthProvider;
  final List<String> dietPrefs;
  final List<String> allergyTags;
  final int calorieGoal;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.phone,
    required this.oauthProvider,
    required this.dietPrefs,
    required this.allergyTags,
    required this.calorieGoal,
    required this.createdAt,
  });

  // API Gateway'den (Node.js) gelen JSON verisini Flutter nesnesine dönüştüren constructor (Factory)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      oauthProvider: json['oauthProvider'] as String? ?? 'STANDART',
      dietPrefs: List<String>.from(json['dietPrefs'] ?? []),
      allergyTags: List<String>.from(json['allergyTags'] ?? []),
      calorieGoal: json['calorieGoal'] as int? ?? 2000, // Varsayılan hedef 2000 kcal
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
    );
  }

  // Kullanıcı profilde değişiklik yaptığında veritabanına göndermek için nesneyi JSON formatına çeviren metod
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'phone': phone,
      'oauthProvider': oauthProvider,
      'dietPrefs': dietPrefs,
      'allergyTags': allergyTags,
      'calorieGoal': calorieGoal,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
