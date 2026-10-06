import '../../domain/models/home_summary_model.dart';

sealed class HomeState {
  const HomeState();
}

class HomeInitial extends HomeState {
  const HomeInitial();
}

class HomeLoading extends HomeState {
  const HomeLoading();
}

class HomeLoaded extends HomeState {
  final HomeSummaryModel summary;
  const HomeLoaded(this.summary);
}

class HomeError extends HomeState {
  final String message;
  const HomeError(this.message);
}
