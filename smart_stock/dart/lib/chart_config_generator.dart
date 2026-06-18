/// chart_config_generator.dart
/// ===========================
/// 跨端适配器前端渲染层 —— 根据模型输出信号动态生成 fl_chart 配置对象。
///
/// 功能：
///   1. 自动在 K 线图上绘制"买入/卖出"箭头标记。
///   2. 生成趋势预测的虚线覆盖层。
///   3. 将注意力权重映射为时间轴高亮区间。
///
/// 遵循 Effective Dart 规范，面向 fl_chart (https://pub.dev/packages/fl_chart) API。

import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'signal_models.dart';

enum TrendDirection { up, down, flat }

class SignalMarker {
  final int index;
  final double price;
  final bool isBuy;
  final double strength;

  const SignalMarker({
    required this.index,
    required this.price,
    required this.isBuy,
    required this.strength,
  });
}

class PredictionOverlay {
  final List<FlSpot> predictedLine;
  final double lowerBound;
  final double upperBound;
  final TrendDirection direction;

  const PredictionOverlay({
    required this.predictedLine,
    required this.lowerBound,
    required this.upperBound,
    required this.direction,
  });
}

class AttentionHighlight {
  final int startIndex;
  final int endIndex;
  final double intensity;

  const AttentionHighlight({
    required this.startIndex,
    required this.endIndex,
    required this.intensity,
  });
}

class ChartConfigGenerator {
  final AnalysisPayload payload;
  final List<double> closePrices;

  ChartConfigGenerator({
    required this.payload,
    required this.closePrices,
  });

  List<SignalMarker> generateSignalMarkers() {
    return payload.signals.map((s) {
      return SignalMarker(
        index: s.index,
        price: s.price,
        isBuy: s.isBuy,
        strength: s.strength,
      );
    }).toList();
  }

  PredictionOverlay generatePredictionOverlay({
    int futureSteps = 10,
  }) {
    final pred = payload.prediction;
    final predReturn = pred.predictedReturn;
    final ci = pred.confidenceInterval;

    final direction = pred.trendProbability.up > pred.trendProbability.down
        ? TrendDirection.up
        : pred.trendProbability.down > pred.trendProbability.up
            ? TrendDirection.down
            : TrendDirection.flat;

    final lastPrice = closePrices.isNotEmpty ? closePrices.last : 0.0;
    final lastIdx = closePrices.length - 1;

    final predictedLine = <FlSpot>[];
    final stepReturn = predReturn / futureSteps;

    for (int i = 1; i <= futureSteps; i++) {
      final projectedPrice = lastPrice * (1 + stepReturn * i);
      predictedLine.add(FlSpot((lastIdx + i).toDouble(), projectedPrice));
    }

    return PredictionOverlay(
      predictedLine: predictedLine,
      lowerBound: ci.lower,
      upperBound: ci.upper,
      direction: direction,
    );
  }

  List<AttentionHighlight> generateAttentionHighlights({
    double threshold = 0.08,
    int minConsecutive = 2,
  }) {
    final weights = payload.attentionWeights;
    if (weights.isEmpty) return [];

    final maxW = weights.reduce(math.max);
    final normalized = weights.map((w) => w / (maxW + 1e-10)).toList();

    final highlights = <AttentionHighlight>[];
    int start = -1;

    for (int i = 0; i < normalized.length; i++) {
      if (normalized[i] >= threshold) {
        start = (start < 0) ? i : start;
      } else {
        if (start >= 0 && (i - start) >= minConsecutive) {
          highlights.add(AttentionHighlight(
            startIndex: start,
            endIndex: i - 1,
            intensity: normalized.sublist(start, i).reduce(math.max),
          ));
        }
        start = -1;
      }
    }

    if (start >= 0 && (normalized.length - start) >= minConsecutive) {
      highlights.add(AttentionHighlight(
        startIndex: start,
        endIndex: normalized.length - 1,
        intensity: normalized.sublist(start).reduce(math.max),
      ));
    }

    return highlights;
  }

  LineChartBarData buildCandlestickLine() {
    final spots = <FlSpot>[];
    for (int i = 0; i < closePrices.length; i++) {
      spots.add(FlSpot(i.toDouble(), closePrices[i]));
    }
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: const Color(0xFF2196F3),
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );
  }

  LineChartBarData buildPredictionLine(PredictionOverlay overlay) {
    return LineChartBarData(
      spots: overlay.predictedLine,
      isCurved: true,
      color: overlay.direction == TrendDirection.up
          ? const Color(0xFF4CAF50)
          : overlay.direction == TrendDirection.down
              ? const Color(0xFFF44336)
              : const Color(0xFFFF9800),
      barWidth: 2,
      dashArray: [6, 4],
      dotData: const FlDotData(show: false),
    );
  }

  List<BetweenBarsData> buildConfidenceBand(PredictionOverlay overlay) {
    if (overlay.predictedLine.isEmpty) return [];

    final lastIdx = closePrices.length - 1;
    final upperSpots = overlay.predictedLine.map((s) {
      final scale = (s.x - lastIdx) / overlay.predictedLine.length;
      return FlSpot(s.x, overlay.upperBound * (1 + scale * 0.5));
    }).toList();
    final lowerSpots = overlay.predictedLine.map((s) {
      final scale = (s.x - lastIdx) / overlay.predictedLine.length;
      return FlSpot(s.x, overlay.lowerBound * (1 - scale * 0.3));
    }).toList();

    return [
      BetweenBarsData(
        fromIndex: 1,
        toIndex: 2,
        color: const Color(0x334CAF50),
      ),
    ];
  }

  LineChartData buildCompleteChart({
    required PredictionOverlay overlay,
  }) {
    final markers = generateSignalMarkers();

    final lineBarsData = <LineChartBarData>[
      buildCandlestickLine(),
      buildPredictionLine(overlay),
    ];

    return LineChartData(
      lineBarsData: lineBarsData,
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 30),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 50),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: overlay.lowerBound,
            color: const Color(0x804CAF50),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
          HorizontalLine(
            y: overlay.upperBound,
            color: const Color(0x804CAF50),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ],
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              return LineTooltipItem(
                '${spot.y.toStringAsFixed(2)}',
                TextStyle(
                  color: spot.barIndex == 0
                      ? const Color(0xFF2196F3)
                      : const Color(0xFF4CAF50),
                ),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  String generateChartSummary() {
    final pred = payload.prediction;
    final trend = pred.trendProbability;
    final direction = trend.up > trend.down ? '看涨' : trend.down > trend.up ? '看跌' : '震荡';

    final buf = StringBuffer();
    buf.writeln('=== 图表配置摘要 ===');
    buf.writeln('股票: ${payload.symbol}');
    buf.writeln('趋势判断: $direction');
    buf.writeln('上涨概率: ${(trend.up * 100).toStringAsFixed(1)}%');
    buf.writeln('下跌概率: ${(trend.down * 100).toStringAsFixed(1)}%');
    buf.writeln('预测收益率: ${(pred.predictedReturn * 100).toStringAsFixed(2)}%');
    buf.writeln('置信区间: [${pred.confidenceInterval.lower}, ${pred.confidenceInterval.upper}]');
    buf.writeln('买入信号: ${payload.buySignals.length} 个');
    buf.writeln('卖出信号: ${payload.sellSignals.length} 个');

    final highlights = generateAttentionHighlights();
    if (highlights.isNotEmpty) {
      buf.writeln('关键时间区间:');
      for (final h in highlights) {
        buf.writeln('  [${h.startIndex} - ${h.endIndex}] 强度: ${h.intensity.toStringAsFixed(3)}');
      }
    }

    return buf.toString();
  }
}
