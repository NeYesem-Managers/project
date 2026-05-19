

import 'package:equatable/equatable.dart';

abstract class ProfileState extends Equatable {
  const ProfileState();
  
  @override
  List<Object?> get props => [];
}

// Durum 1: Sayfa ilk açılırken veriler henüz yükleniyorken gösterilecek durum
class ProfileLoadingState extends ProfileState {
  const ProfileLoadingState(); // Hata vermemesi için const eklendi
}

// Durum 2: Veriler başarıyla hafızaya alındığında ve arayüze güncel halini sunarkenki durum
class ProfileLoadedState extends ProfileState {
  final String currentDiet;
  final List<String> currentAllergies;
  final int currentCalorieGoal;

  const ProfileLoadedState({
    required this.currentDiet,
    required this.currentAllergies,
    required this.currentCalorieGoal,
  });

  @override
  List<Object?> get props => [currentDiet, currentAllergies, currentCalorieGoal];
}

// Durum 3: Veritabanı veya API bağlantısında bir sorun çıkarsa gösterilecek durum
class ProfileErrorState extends ProfileState {
  final String errorMessage;
  const ProfileErrorState(this.errorMessage);

  @override
  List<Object?> get props => [errorMessage];
}