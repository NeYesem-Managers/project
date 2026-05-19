

import 'package:equatable/equatable.dart';

abstract class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object?> get props => [];
}

// 1. Olay: Profil ekranı ilk açıldığında mevcut verileri yükleme olayı
class LoadProfileEvent extends ProfileEvent {}

// 2. Olay: Kullanıcı diyet tercihini değiştirdiğinde tetiklenecek olay
class UpdateDietPreferenceEvent extends ProfileEvent {
  final String selectedDiet;
  const UpdateDietPreferenceEvent(this.selectedDiet);

  @override
  List<Object?> get props => [selectedDiet];
}

// 3. Olay: Kullanıcı bir alerjen eklediğinde veya çıkardığında tetiklenecek olay
class UpdateAllergyTagsEvent extends ProfileEvent {
  final List<String> updatedAllergies;
  const UpdateAllergyTagsEvent(this.updatedAllergies);

  @override
  List<Object?> get props => [updatedAllergies];
}