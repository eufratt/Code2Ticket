import 'package:code2ticket/features/discover/domain/models/giveaway_model.dart';
import 'package:code2ticket/features/draw/domain/models/winner_model.dart';

class DrawDetailModel {
  final GiveawayModel giveaway;
  final String? drawId;
  final String? drawStatus;
  final DateTime? drawnAt;
  final String? seedCommitment;
  final String? txHash;
  final List<WinnerModel> winners;

  const DrawDetailModel({
    required this.giveaway,
    this.drawId,
    this.drawStatus,
    this.drawnAt,
    this.seedCommitment,
    this.txHash,
    this.winners = const [],
  });

  bool get isDrawn => drawStatus == 'completed' || drawStatus == 'verified_onchain';
  bool get isVerifiedOnchain =>
      drawStatus == 'verified_onchain' || (txHash != null && txHash!.isNotEmpty);

  DrawDetailModel copyWith({
    GiveawayModel? giveaway,
    String? drawId,
    String? drawStatus,
    DateTime? drawnAt,
    String? seedCommitment,
    String? txHash,
    List<WinnerModel>? winners,
  }) {
    return DrawDetailModel(
      giveaway: giveaway ?? this.giveaway,
      drawId: drawId ?? this.drawId,
      drawStatus: drawStatus ?? this.drawStatus,
      drawnAt: drawnAt ?? this.drawnAt,
      seedCommitment: seedCommitment ?? this.seedCommitment,
      txHash: txHash ?? this.txHash,
      winners: winners ?? this.winners,
    );
  }
}
