import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../bloc/profile_bloc.dart';
import '../bloc/profile_event.dart';
import '../bloc/profile_state.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // Doğru Değişken Tanımlama Yapısı:
  final List<String> _dietOptions = const [
    'Standart',
    'Vejetaryen',
    'Vegan',
    'Glutensiz',
    'Ketojenik',
    'Protein Ağırlıklı',
  ];

  final List<String> _allergyOptions = const [
    'Gluten',
    'Laktoz',
    'Yer Fıstığı',
    'Deniz Ürünleri',
    'Soya',
    'Yumurta',
  ];

  @override
  Widget build(BuildContext context) {
    // KOPUKLUĞU ÇÖZEN ADIM: Dıştaki BlocProvider sarmalını kaldırdık.
    // Doğrudan Scaffold ile başlayarak MainLayout'taki ana hafızaya bağlandık.
    return Scaffold(
      backgroundColor: AppColors.surfaceBackground,
      appBar: AppBar(
        title: const Text(
          'Profil ve Hedefler',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primaryOrange,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, state) {
          if (state is ProfileLoadingState) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryOrange),
            );
          }

          if (state is ProfileLoadedState) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(
                    'Kişiselleştirme Merkezi',
                    Icons.auto_awesome,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16.0, left: 4.0),
                    child: Text(
                      'Seçtiğiniz diyet ve alerji bilgileri BLoC katmanında güvenle saklanır.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),

                  // 1. DİYET SEÇİM BÖLÜMÜ
                  _buildCardContainer(
                    title: 'Diyet Tercihi',
                    icon: Icons.restaurant_menu,
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: _dietOptions.map((diet) {
                        final isSelected = state.currentDiet == diet;
                        return ChoiceChip(
                          label: Text(diet),
                          selected: isSelected,
                          selectedColor: AppColors.healthGreen.withValues(
                            alpha: 0.2,
                          ),
                          checkmarkColor: AppColors.healthGreen,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? AppColors.healthGreen
                                : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              context.read<ProfileBloc>().add(
                                UpdateDietPreferenceEvent(diet),
                              );
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. ALERJİ SEÇİM BÖLÜMÜ
                  _buildCardContainer(
                    title: 'Alerjen Uyarıları',
                    icon: Icons.warning_amber_rounded,
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: _allergyOptions.map((allergy) {
                        final isSelected = state.currentAllergies.contains(
                          allergy,
                        );
                        return FilterChip(
                          label: Text(allergy),
                          selected: isSelected,
                          selectedColor: Colors.red.withValues(alpha: 0.1),
                          checkmarkColor: Colors.red,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.red : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            final List<String> updatedAllergies = List.from(
                              state.currentAllergies,
                            );
                            if (selected) {
                              updatedAllergies.add(allergy);
                            } else {
                              updatedAllergies.remove(allergy);
                            }
                            context.read<ProfileBloc>().add(
                              UpdateAllergyTagsEvent(updatedAllergies),
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. KALORİ HEDEFİ BÖLÜMÜ
                  _buildCardContainer(
                    title: 'Günlük Kalori Hedefi',
                    icon: Icons.local_fire_department_rounded,
                    child: Center(
                      child: Text(
                        '${state.currentCalorieGoal} kcal',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.partnerBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'BLoC Verileri Onaylandı! Güncel Diyet: ${state.currentDiet}',
                            ),
                            backgroundColor: AppColors.healthGreen,
                          ),
                        );
                      },
                      child: const Text(
                        'Tercihleri Sisteme İşle',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          if (state is ProfileErrorState) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  state.errorMessage,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildCardContainer({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryOrange, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 0.8),
          child,
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.black54, size: 20),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}
