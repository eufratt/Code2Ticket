import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:code2ticket/features/input_code/domain/models/redeem_result_model.dart';
import 'package:code2ticket/features/input_code/domain/repositories/input_code_repository.dart';
import 'package:code2ticket/features/input_code/presentation/controllers/input_code_controller.dart';
import 'package:code2ticket/features/input_code/presentation/controllers/input_code_state.dart';
import 'package:code2ticket/features/input_code/presentation/widgets/code_input_formatter.dart';

class MockInputCodeRepository implements InputCodeRepository {
  final RedeemResultModel Function(String code, double? lat, double? lng) onRedeem;

  MockInputCodeRepository({required this.onRedeem});

  @override
  Future<RedeemResultModel> redeemCode(
    String code, {
    double? latitude,
    double? longitude,
  }) async {
    return onRedeem(code, latitude, longitude);
  }
}

void main() {
  group('CodeInputFormatter Tests', () {
    final formatter = CodeInputFormatter();

    test('Converts lowercase input to uppercase', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(text: 'game-pkw-001');

      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'GAME-PKW-001');
    });

    test('Removes non-alphanumeric characters while preserving hyphens', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(text: 'ABC#@!-123_456');

      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'ABC-123456');
    });

    test('Auto-dashes 12 character continuous code into XXXX-XXXX-XXXX', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(text: 'ABCD1234EFGH');

      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'ABCD-1234-EFGH');
    });

    test('Auto-dashes both first and second hyphens when typing continuously', () {
      // User typed "foodugm0002"
      const oldValue = TextEditingValue(text: 'FOOD-UGM0');
      const newValue = TextEditingValue(text: 'FOOD-UGM0002');

      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'FOOD-UGM0-002');
    });

    test('Preserves custom placed hyphens like GAME-PKW-001', () {
      const oldValue = TextEditingValue(text: 'GAME-PKW-');
      const newValue = TextEditingValue(text: 'GAME-PKW-001');

      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'GAME-PKW-001');
    });
  });

  group('RedeemResultModel Tests', () {
    test('Parses successful redeem JSON with ticket details', () {
      final json = {
        'success': true,
        'message': 'Tiket berhasil diterbitkan!',
        'ticket': {
          'id': 'ticket-123',
          'ticket_number': 'TKT-GAM-00001',
          'giveaway_id': 'gw-001',
          'giveaway_title': 'Turnamen Mobile Legends DIY',
          'status': 'waiting_for_draw',
          'draw_at': '2026-11-01T20:00:00Z',
        },
      };

      final model = RedeemResultModel.fromJson(json);
      expect(model.success, isTrue);
      expect(model.ticket, isNotNull);
      expect(model.ticket!.ticketNumber, 'TKT-GAM-00001');
      expect(model.ticket!.giveawayTitle, 'Turnamen Mobile Legends DIY');
      expect(model.ticket!.status, 'waiting_for_draw');
    });

    test('Parses error JSON with descriptive error message', () {
      final json = {
        'success': false,
        'error': 'Kode partisipasi tidak terdaftar dalam sistem.',
      };

      final model = RedeemResultModel.fromJson(json);
      expect(model.success, isFalse);
      expect(model.ticket, isNull);
      expect(model.error, 'Kode partisipasi tidak terdaftar dalam sistem.');
    });
  });

  group('InputCodeController Tests', () {
    test('Empty code sets InputCodeError without calling repository', () async {
      final container = ProviderContainer(
        overrides: [
          inputCodeRepositoryProvider.overrideWithValue(
            MockInputCodeRepository(
              onRedeem: (code, lat, lng) => throw UnimplementedError(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(inputCodeControllerProvider.notifier);
      final success = await controller.redeemCode('   ');

      expect(success, isFalse);
      expect(container.read(inputCodeControllerProvider), isA<InputCodeError>());
    });

    test('Successful redeem transitions to InputCodeSuccess', () async {
      final mockRepo = MockInputCodeRepository(
        onRedeem: (code, lat, lng) => const RedeemResultModel(
          success: true,
          message: 'Berhasil',
          ticket: RedeemTicketInfo(
            id: 't-1',
            ticketNumber: 'TKT-GAM-00001',
            giveawayId: 'gw-1',
            giveawayTitle: 'MLBB Tournament',
            status: 'waiting_for_draw',
          ),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          inputCodeRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(inputCodeControllerProvider.notifier);
      final success = await controller.redeemCode('GAME-PKW-001');

      expect(success, isTrue);
      final state = container.read(inputCodeControllerProvider);
      expect(state, isA<InputCodeSuccess>());
      expect((state as InputCodeSuccess).result.ticket?.ticketNumber, 'TKT-GAM-00001');
    });

    test('Failed redeem with error transitions to InputCodeError', () async {
      final mockRepo = MockInputCodeRepository(
        onRedeem: (code, lat, lng) => const RedeemResultModel(
          success: false,
          message: 'Gagal',
          error: 'Kode partisipasi ini sudah digunakan pada tiket lain.',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          inputCodeRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(inputCodeControllerProvider.notifier);
      final success = await controller.redeemCode('ALREADY-USED');

      expect(success, isFalse);
      final state = container.read(inputCodeControllerProvider);
      expect(state, isA<InputCodeError>());
      expect(
        (state as InputCodeError).message,
        'Kode partisipasi ini sudah digunakan pada tiket lain.',
      );
    });

    test('Reset returns state to InputCodeInitial', () async {
      final mockRepo = MockInputCodeRepository(
        onRedeem: (code, lat, lng) => const RedeemResultModel(
          success: true,
          message: 'Berhasil',
          ticket: RedeemTicketInfo(
            id: 't-1',
            ticketNumber: 'TKT-001',
            giveawayId: 'gw-1',
            giveawayTitle: 'Promo',
            status: 'waiting_for_draw',
          ),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          inputCodeRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(inputCodeControllerProvider.notifier);
      await controller.redeemCode('PROMO-123');
      expect(container.read(inputCodeControllerProvider), isA<InputCodeSuccess>());

      controller.reset();
      expect(container.read(inputCodeControllerProvider), isA<InputCodeInitial>());
    });
  });
}
