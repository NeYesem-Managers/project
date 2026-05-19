import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../profile/bloc/profile_bloc.dart';
import '../../profile/bloc/profile_state.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Mock Geniş Yemek Havuzu
  final List<Map<String, dynamic>> _foodPool = [
    {
      'id': 'p1',
      'title': 'Fit Tavuk Bowl',
      'restaurant': 'Sağlıklı Mutfak',
      'calorie': 520,
      'minPrice': 189.0,
      'description': 'Protein ağırlıklı yapay zeka akşam menüsü önerisi.',
      'tag': 'AI Öneri',
      'tagColor': AppColors.primaryOrange,
      'isVegan': false,
      'allergens': ['Gluten'],
    },
    {
      'id': 'p2',
      'title': 'Vegan Noodle',
      'restaurant': 'Asia Box',
      'calorie': 430,
      'minPrice': 164.0,
      'description':
          'Mutfak geçmişinize göre fiyat avantajlı vegan akşam yemeği.',
      'tag': 'Gerçek İndirim',
      'tagColor': AppColors.healthGreen,
      'isVegan': true,
      'allergens': ['Soya', 'Gluten'],
    },
    {
      'id': 'p3',
      'title': 'Ezogelin Çorbası & Mevsim Salata',
      'restaurant': 'Yöresel Ev Yemekleri',
      'calorie': 310,
      'minPrice': 95.0,
      'description': 'Hafif ve bütçe dostu, tamamen bitkisel menü.',
      'tag': 'Bütçe Dostu',
      'tagColor': AppColors.partnerBlue,
      'isVegan': true,
      'allergens': [],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBackground,
      appBar: AppBar(
        title: const Text(
          'NeYesem',
          style: TextStyle(
            color: AppColors.primaryOrange,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        backgroundColor: AppColors.surfaceLight,
        elevation: 0,
      ),
      body: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, state) {
          // 1. DURUM: Loading
          if (state is ProfileLoadingState) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryOrange),
            );
          }

          // 2. DURUM: Error (Hatalı text yapısı const kaldırılarak ve düzeltilerek çözüldü)
          if (state is ProfileErrorState) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    SizedBox(height: 16),
                    Text(
                      'Profil bilgileri yüklenirken bir hata oluştu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            );
          }

          // 3. DURUM: ProfileLoadedState
          String userDiet = 'Standart';
          List<String> userAllergies = [];

          if (state is ProfileLoadedState) {
            userDiet = state.currentDiet;
            userAllergies = state.currentAllergies;
          }

          // YAPAY ZEKA FİLTRELEME ALGORİTMASI
          List<Map<String, dynamic>> suggestedFoods = _foodPool.where((food) {
            if (userDiet == 'Vegan' && !(food['isVegan'] as bool)) {
              return false;
            }
            return true;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              const Text(
                'Merhaba 👋',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                'Profiliniz: $userDiet Diyet | ${userAllergies.length} Aktif Alerjen',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),

              ...suggestedFoods.map(
                (item) => _buildSuggestionCard(item, userAllergies),
              ),
            ],
          );
        },
      ),
    );
  }

  // Akıllı Yemek Kartı Bileşeni
  Widget _buildSuggestionCard(
    Map<String, dynamic> item,
    List<String> userAllergies,
  ) {
    final Color tagColor = item['tagColor'] as Color;
    final List<String> foodAllergens = List<String>.from(
      item['allergens'] ?? [],
    );

    final bool hasAllergyConflict = foodAllergens.any(
      (allergen) => userAllergies.contains(allergen),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: hasAllergyConflict
            ? Border.all(color: Colors.red.shade400, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst Satır - Spacer kullanımı
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tagColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item['tag'].toString(),
                    style: TextStyle(
                      color: tagColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(), 
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${item['calorie']} kcal', // ÇÖZÜM: $ işareti eklendi
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Başlık ve Fiyat Satırı - Spacer kullanımı
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['title'].toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item['restaurant'].toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(), 
                Text(
                  '${(item['minPrice'] as double).toStringAsFixed(0)} TL', // ÇÖZÜM: $ işareti eklendi
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryOrange,
                  ),
                ),
              ],
            ),

            // 🚨 KRİTİK ALERJİ ALARMI SÜZGECİ
            if (hasAllergyConflict) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'DİKKAT: Bu yemek seçtiğiniz Alerjen maddeleri içerir!',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            Text(
              item['description'].toString(),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
            const Divider(height: 24, thickness: 0.5),

            // Geri Bildirim Butonları
            Row(
              children: [
                const Spacer(), 
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.thumb_down_alt_outlined,
                    size: 18,
                    color: Colors.grey,
                  ),
                  label: const Text(
                    'Beğenme',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.thumb_up_alt_rounded,
                    size: 18,
                    color: AppColors.healthGreen,
                  ),
                  label: const Text(
                    'Beğen',
                    style: TextStyle(
                      color: AppColors.healthGreen,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
