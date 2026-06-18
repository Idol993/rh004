/// signal_models.dart
/// ==================
/// 端云协同智能炒股分析系统 - Dart 反序列化数据模型。
///
/// 遵循 Effective Dart 规范，从后端 JSON Schema 反序列化为强类型对象。

import 'dart:convert';
import 'dart:math' as math;

class TrendProbability {
  final double up;
  final double down;
  final double flat;

  const TrendProbability({
    required this.up,
    required this.down,
    required this.flat,
  });

  factory TrendProbability.fromJson(Map<String, dynamic> json) =>
      TrendProbability(
        up: (json['up'] as num).toDouble(),
        down: (json['down'] as num).toDouble(),
        flat: (json['flat'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'up': up, 'down': down, 'flat': flat};

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

  factory ConfidenceInterval.fromJson(Map<String, dynamic> json) =>
      ConfidenceInterval(
        lower: (json['lower'] as num).toDouble(),
        upper: (json['upper'] as num).toDouble(),
        level: (json['level'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() =>
      {'lower': lower, 'upper': upper, 'level': level};

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

  factory PredictionResult.fromJson(Map<String, dynamic> json) =>
      PredictionResult(
        trendProbability:
            TrendProbability.fromJson(json['trend_probability'] as Map<String, dynamic>),
        confidenceInterval:
            ConfidenceInterval.fromJson(json['confidence_interval'] as Map<String, dynamic>),
        predictedReturn: (json['predicted_return'] as num).toDouble(),
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

  factory SignalPoint.fromJson(Map<String, dynamic> json) => SignalPoint(
        index: json['index'] as int,
        type: json['type'] as String,
        price: (json['price'] as num).toDouble(),
        strength: (json['strength'] as num).toDouble(),
      );

  bool get isBuy => type == 'buy';
  bool get isSell => type == 'sell';

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

  factory AnalysisPayload.fromJson(Map<String, dynamic> json) =>
      AnalysisPayload(
        version: json['version'] as String,
        symbol: json['symbol'] as String,
        timestamp: json['timestamp'] as String,
        prediction:
            PredictionResult.fromJson(json['prediction'] as Map<String, dynamic>),
        signals: (json['signals'] as List)
            .map((e) => SignalPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        attentionWeights: (json['attention_weights'] as List)
            .map((e) => (e as num).toDouble())
            .toList(),
      );

  factory AnalysisPayload.fromJsonString(String str) =>
      AnalysisPayload.fromJson(jsonDecode(str) as Map<String, dynamic>);

  List<SignalPoint> get buySignals =>
      signals.where((s) => s.isBuy).toList();

  List<SignalPoint> get sellSignals =>
      signals.where((s) => s.isSell).toList();

  @override
  String toString() =>
      'AnalysisPayload(symbol: $symbol, prediction: $prediction, signals: ${signals.length})';
}
