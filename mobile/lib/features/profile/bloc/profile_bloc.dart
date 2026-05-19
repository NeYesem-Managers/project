import 'package:flutter_bloc/flutter_bloc.dart';
import 'profile_event.dart';
import 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc() : super(ProfileLoadingState()) {
    
    // 1. Yükleme olayı tetiklendiğinde çalışacak mantık
    on<LoadProfileEvent>((event, emit) async {
      emit(ProfileLoadingState());
      try {
        // İleride buraya backend API'sinden veri çekme kodu gelecek.
        // Şimdilik varsayılan başlangıç değerlerini yüklüyoruz (Mock veritabanı gibi).
        await Future.delayed(const Duration(milliseconds: 500)); // Minik bir gecikme simülasyonu
        emit(const ProfileLoadedState(
          currentDiet: 'Standart',
          currentAllergies: [],
          currentCalorieGoal: 2000,
        ));
      } catch (e) {
        emit(ProfileErrorState('Profil verileri yüklenemedi: $e'));
      }
    });

    // 2. Diyet değiştirme olayı tetiklendiğinde çalışacak mantık
    on<UpdateDietPreferenceEvent>((event, emit) {
      if (state is ProfileLoadedState) {
        final currentState = state as ProfileLoadedState;
        // Mevcut durumu bozmadan sadece diyet bilgisini güncelleyip yeni state fırlatıyoruz
        emit(ProfileLoadedState(
          currentDiet: event.selectedDiet,
          currentAllergies: currentState.currentAllergies,
          currentCalorieGoal: currentState.currentCalorieGoal,
        ));
      }
    });

    // 3. Alerji değiştirme olayı tetiklendiğinde çalışacak mantık
    on<UpdateAllergyTagsEvent>((event, emit) {
      if (state is ProfileLoadedState) {
        final currentState = state as ProfileLoadedState;
        emit(ProfileLoadedState(
          currentDiet: currentState.currentDiet,
          currentAllergies: event.updatedAllergies,
          currentCalorieGoal: currentState.currentCalorieGoal,
        ));
      }
    });
  }
}