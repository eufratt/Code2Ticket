// Pembaca JSON defensif: field hilang / bertipe salah menjadi null atau nilai bawaan, tidak melempar.

String? asString(dynamic v) => v is String ? v : null;

int asInt(dynamic v, [int fallback = 0]) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v) : null) ?? fallback;

double? asDouble(dynamic v) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

/// Tanggal ISO-8601 (server mengirim UTC "...Z") -> DateTime zona lokal perangkat.
DateTime? asDate(dynamic v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

Map<String, dynamic>? asMap(dynamic v) =>
    v is Map<String, dynamic> ? v : null;

/// Mengurai daftar; elemen yang rusak (parser mengembalikan null) dilewati.
List<T> parseList<T>(dynamic v, T? Function(dynamic) parse) =>
    v is List ? [for (final e in v) ?parse(e)] : <T>[];
