import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../profile/bloc/profile_bloc.dart';
import '../../profile/bloc/profile_event.dart';
import '../../../core/navigation/main_layout.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String selectedDiet = 'Standart';
  List<String> selectedAllergies = [];

  final List<String> diets = const ['Standart', 'Vejetaryen', 'Vegan', 'Glutensiz'];
  final List<String> allergies = const ['Gluten', 'Laktoz', 'Yer Fıstığı', 'Soya'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Beslenme Profilin 🥗', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Yapay zeka sana en uygun yemekleri bulabilmek için bu bilgilere ihtiyaç duyar.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              
              const Text('Diyet Tercihin', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: diets.map((diet) => ChoiceChip(
                  label: Text(diet),
                  selected: selectedDiet == diet,
                  onSelected: (val) => setState(() => selectedDiet = diet),
                )).toList(),
              ),
              
              const SizedBox(height: 30),
              const Text('Alerjilerin', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: allergies.map((allergy) => FilterChip(
                  label: Text(allergy),
                  selected: selectedAllergies.contains(allergy),
                  onSelected: (val) {
                    setState(() {
                      val ? selectedAllergies.add(allergy) : selectedAllergies.remove(allergy);
                    });
                  },
                )).toList(),
              ),
              
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.healthGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  onPressed: () {
                    // SEÇİMLERİ BLOC'A YÜKLÜYORUZ
                    context.read<ProfileBloc>().add(UpdateDietPreferenceEvent(selectedDiet));
                    context.read<ProfileBloc>().add(UpdateAllergyTagsEvent(selectedAllergies));
                    
                    // ANA SAYFAYA GEÇİŞ
                    Navigator.pushAndRemoveUntil(
                      context, 
                      MaterialPageRoute(builder: (_) => const MainLayout()),
                      (route) => false
                    );
                  },
                  child: const Text('Anketini Tamamla ve Başla', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}