/// signal_models.dart
/// ==================
/// 端云协同智能炒股分析系统 - Dart 反序列化数据模型。
///
/// 遵循 Effective Dart 规范，从后端 JSON Schema 反序列化为强类型对象。
///
/// 空值安全设计：
///   - 所有字段都有合理的默认值（0.0, "", [], etc.）
///   - 解析时遇到 null 或类型不匹配时，自动回退到默认值
///   - 使用 ? 操作符和 as? 安全转型
///   - fromJsonString 方法捕获异常，解析失败返回空对象

import 'dart:convert';

class TrendProbability {
  final double up;
  final double down;
  final double flat;

  const TrendProbability({
    required this.up,
    required this.down,
    required this.flat,
  });

  factory TrendProbability.fromJson(Map<String, dynamic>? json) =>
      TrendProbability(
        up: (json?['up'] as num?)?.toDouble() ?? 0.0,
        down: (json?['down'] as num?)?.toDouble() ?? 0.0,
        flat: (json?['flat'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {'up': up, 'down': down, 'flat': flat};

  double get primaryProbability =>
      up > down ? (up > flat ? up : flat) : (down > flat ? down : flat);

  String get primaryDirection =>
      up > down ? (up > flat ? 'up' : 'flat') : (down > flat ? 'down' : 'flat');

  @override
  String toString() => 'TrendProbability(up: $up, down: $down, flat: $flat)';
}

class ConfidenceInterval {
  final double lower;
  final double upper;
  final double level;

  const ConfidenceInterval({
    required this.lower,
    required this.upper,
    required this.level,
  });

  factory ConfidenceInterval.fromJson(Map<String, dynamic>? json) =>
      ConfidenceInterval(
        lower: (json?['lower'] as num?)?.toDouble() ?? 0.0,
        upper: (json?['upper'] as num?)?.toDouble() ?? 0.0,
        level: (json?['level'] as num?)?.toDouble() ?? 0.95,
      );

  Map<String, dynamic> toJson() =>
      {'lower': lower, 'upper': upper, 'level': level};

  double get width => upper - lower;

  double get center => (lower + upper) / 2;

  @override
  String toString() =>
      'ConfidenceInterval(lower: $lower, upper: $upper, level: $level)';
}

class PredictionResult {
  final TrendProbability trendProbability;
  final ConfidenceInterval confidenceInterval;
  final double predictedReturn;

  const PredictionResult({
    required this.trendProbability,
    required this.confidenceInterval,
    required this.predictedReturn,
  });

  factory PredictionResult.fromJson(Map<String, dynamic>? json) =>
      PredictionResult(
        trendProbability: TrendProbability.fromJson(
            json?['trend_probability'] as Map<String, dynamic>?),
        confidenceInterval: ConfidenceInterval.fromJson(
            json?['confidence_interval'] as Map<String, dynamic>?),
        predictedReturn: (json?['predicted_return'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  String toString() =>
      'PredictionResult(trend: $trendProbability, ci: $confidenceInterval, ret: $predictedReturn)';
}

class SignalPoint {
  final int index;
  final String type;
  final double price;
  final double strength;

  const SignalPoint({
    required this.index,
    required this.type,
    required this.price,
    required this.strength,
  });

  factory SignalPoint.fromJson(Map<String, dynamic>? json) => SignalPoint(
        index: (json?['index'] as int?) ?? 0,
        type: (json?['type'] as String?) ?? 'unknown',
        price: (json?['price'] as num?)?.toDouble() ?? 0.0,
        strength: (json?['strength'] as num?)?.toDouble() ?? 0.0,
      );

  bool get isBuy => type == 'buy';
  bool get isSell => type == 'sell';
  bool get isValid => isBuy || isSell;

  @override
  String toString() =>
      'SignalPoint(index: $index, type: $type, price: $price, strength: $strength)';
}

class AnalysisPayload {
  final String version;
  final String symbol;
  final String timestamp;
  final PredictionResult prediction;
  final List<SignalPoint> signals;
  final List<double> attentionWeights;

  const AnalysisPayload({
    required this.version,
    required this.symbol,
    required this.timestamp,
    required this.prediction,
    required this.signals,
    required this.attentionWeights,
  });

  factory AnalysisPayload.empty() => AnalysisPayload(
        version: '1.0',
        symbol: '',
        timestamp: '',
        prediction: PredictionResult(
          trendProbability: const TrendProbability(up: 0, down: 0, flat: 1),
          confidenceInterval:
              const ConfidenceInterval(lower: 0, upper: 0, level: 0.95),
          predictedReturn: 0.0,
        ),
        signals: const [],
        attentionWeights: const [],
      );

  factory AnalysisPayload.fromJson(Map<String, dynamic>? json) =>
      AnalysisPayload(
        version: (json?['version'] as String?) ?? '1.0',
        symbol: (json?['symbol'] as String?) ?? '',
        timestamp: (json?['timestamp'] as String?) ?? '',
        prediction: PredictionResult.fromJson(
            json?['prediction'] as Map<String, dynamic>?),
        signals: (json?['signals'] as List?)
                ?.map((e) =>
                    SignalPoint.fromJson(e as Map<String, dynamic>?))
                .where((s) => s.isValid)
                .toList() ??
            const [],
        attentionWeights: (json?['attention_weights'] as List?)
                ?.map((e) => (e as num?)?.toDouble() ?? 0.0)
                .toList() ??
            const [],
      );

  factory AnalysisPayload.fromJsonString(String? str) {
    if (str == null || str.isEmpty) {
      return AnalysisPayload.empty();
    }
    try {
      return AnalysisPayload.fromJson(
          jsonDecode(str) as Map<String, dynamic>?);
    } catch (e) {
      return AnalysisPayload.empty();
    }
  }

  List<SignalPoint> get buySignals =>
      signals.where((s) => s.isBuy).toList();

  List<SignalPoint> get sellSignals =>
      signals.where((s) => s.isSell).toList();

  bool get hasSignals => signals.isNotEmpty;
  bool get hasAttentionWeights => attentionWeights.isNotEmpty;
  bool get isEmpty => symbol.isEmpty;

  @override
  String toString() =>
      'AnalysisPayload(symbol: $symbol, prediction: $prediction, signals: ${signals.length})';
}
