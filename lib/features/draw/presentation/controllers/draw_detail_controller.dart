import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:code2ticket/features/draw/domain/models/draw_detail_model.dart';
import 'draw_controller.dart';

final drawDetailProvider =
    FutureProvider.family<DrawDetailModel, String>((ref, giveawayId) async {
  final repository = ref.watch(drawRepositoryProvider);
  return repository.getDrawDetail(giveawayId);
});
