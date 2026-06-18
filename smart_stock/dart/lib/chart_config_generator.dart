/// chart_config_generator.dart
/// ===========================
/// 跨端适配器前端渲染层 —— 根据模型输出信号动态生成 fl_chart 配置对象。
///
/// 功能：
///   1. 自动在 K 线图上绘制"买入/卖出"箭头标记
///   2. 生成趋势预测的虚线覆盖层
///   3. 将注意力权重映射为时间轴高亮区间
///   4. 绘制置信区间上下界
///
/// 遵循 Effective Dart 规范，面向 fl_chart (https://pub.dev/packages/fl_chart) API。

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'signal_models.dart';

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
  final String direction;

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

/// 完整的图表配置打包
class ChartConfig {
  final LineChartData chartData;
  final List<SignalMarker> markers;
  final PredictionOverlay overlay;
  final List<AttentionHighlight> highlights;

  const ChartConfig({
    required this.chartData,
    required this.markers,
    required this.overlay,
    required this.highlights,
  });
}

class ChartConfigGenerator {
  final AnalysisPayload payload;
  final List<double> closePrices;
  final int futureSteps;
  final double arrowSize;

  ChartConfigGenerator({
    required this.payload,
    required this.closePrices,
    this.futureSteps = 10,
    this.arrowSize = 8,
  });

  Color get _upColor => const Color(0xFF4CAF50);
  Color get _downColor => const Color(0xFFF44336);
  Color get _flatColor => const Color(0xFFFF9800);
  Color get _kLineColor => const Color(0xFF2196F3);
  Color get _highlightColor => const Color(0xFFFFEB3B);

  /// 生成买入/卖出信号标记
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

  /// 生成趋势预测的虚线覆盖层
  PredictionOverlay generatePredictionOverlay() {
    final pred = payload.prediction;
    final predReturn = pred.predictedReturn;
    final ci = pred.confidenceInterval;
    final direction = pred.trendProbability.primaryDirection;

    final lastPrice = closePrices.isNotEmpty ? closePrices.last : 0.0;
    final lastIdx = closePrices.length - 1;

    final predictedLine = <FlSpot>[];

    predictedLine.add(FlSpot(lastIdx.toDouble(), lastPrice));

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

  /// 生成注意力权重高亮区间
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

  /// 构建收盘价 K 线
  LineChartBarData _buildKLine() {
    final spots = <FlSpot>[];
    for (int i = 0; i < closePrices.length; i++) {
      if (!closePrices[i].isNaN && !closePrices[i].isInfinite) {
        spots.add(FlSpot(i.toDouble(), closePrices[i]));
      }
    }
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: _kLineColor,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );
  }

  /// 构建预测趋势虚线
  LineChartBarData _buildPredictionLine(PredictionOverlay overlay) {
    Color lineColor;
    switch (overlay.direction) {
      case 'up':
        lineColor = _upColor;
        break;
      case 'down':
        lineColor = _downColor;
        break;
      default:
        lineColor = _flatColor;
    }

    return LineChartBarData(
      spots: overlay.predictedLine,
      isCurved: true,
      color: lineColor,
      barWidth: 2,
      dashArray: [6, 4],
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) {
          if (index == 0) {
            return FlDotCirclePainter(
              color: lineColor,
              strokeColor: Colors.white,
              strokeWidth: 2,
              radius: 4,
            );
          }
          return FlDotCirclePainter(
            color: lineColor,
            strokeColor: Colors.white,
            strokeWidth: 1,
            radius: 2,
          );
        },
      ),
    );
  }

  /// 构建买卖信号箭头
  List<LineChartBarData> _buildSignalMarkers(
    List<SignalMarker> markers,
    List<FlSpot> klineSpots,
  ) {
    if (markers.isEmpty) return [];

    final lineBars = <LineChartBarData>[];

    for (final marker in markers) {
      final color = marker.isBuy ? _upColor : _downColor;
      final spots = <FlSpot>[];

      for (final spot in klineSpots) {
        if (spot.x.toInt() == marker.index) {
          final yOffset = marker.isBuy ? -0.5 : 0.5;
          spots.add(FlSpot(spot.x, spot.y + yOffset));
          break;
        }
      }

      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: 0,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCustomPainter(
                isBuy: marker.isBuy,
                color: color,
                size: arrowSize,
                strength: marker.strength,
              );
            },
          ),
        ),
      );
    }

    return lineBars;
  }

  /// 构建注意力高亮区间（使用 between bars）
  List<BetweenBarsData> _buildAttentionHighlights(
    List<AttentionHighlight> highlights,
  ) {
    final bars = <BetweenBarsData>[];
    if (highlights.isEmpty) return bars;
    return bars;
  }

  /// 构建额外线条（置信区间）
  ExtraLinesData _buildExtraLines(PredictionOverlay overlay) {
    final lines = <HorizontalLine>[];

    if (overlay.lowerBound > 0) {
      lines.add(
        HorizontalLine(
          y: overlay.lowerBound,
          color: _upColor.withOpacity(0.5),
          strokeWidth: 1,
          dashArray: [4, 4],
          label: HorizontalLineLabel(
            show: true,
            alignment: Alignment.topRight,
            padding: const EdgeInsets.only(right: 8, top: -8),
            style: TextStyle(
              color: _upColor,
              fontSize: 10,
            ),
            labelResolver: (line) => ' 低 ${overlay.lowerBound.toStringAsFixed(2)}',
          ),
        ),
      );
    }

    if (overlay.upperBound > 0) {
      lines.add(
        HorizontalLine(
          y: overlay.upperBound,
          color: _downColor.withOpacity(0.5),
          strokeWidth: 1,
          dashArray: [4, 4],
          label: HorizontalLineLabel(
            show: true,
            alignment: Alignment.bottomRight,
            padding: const EdgeInsets.only(right: 8),
            style: TextStyle(
              color: _downColor,
              fontSize: 10,
            ),
            labelResolver: (line) => ' 高 ${overlay.upperBound.toStringAsFixed(2)}',
          ),
        ),
      );
    }

    return ExtraLinesData(
      horizontalLines: lines,
    );
  }

  /// 一次性生成完整的图表配置
  ChartConfig buildChartConfig() {
    final markers = generateSignalMarkers();
    final overlay = generatePredictionOverlay();
    final highlights = generateAttentionHighlights();

    final klineBar = _buildKLine();
    final predictionBar = _buildPredictionLine(overlay);
    final signalBars = _buildSignalMarkers(markers, klineBar.spots);

    final lineBarsData = <LineChartBarData>[
      klineBar,
      predictionBar,
      ...signalBars,
    ];

    final maxX = closePrices.length + futureSteps.toDouble();
    final allPrices = <double>[];
    for (final s in klineBar.spots) {
      allPrices.add(s.y);
    }
    for (final s in overlay.predictedLine) {
      allPrices.add(s.y);
    }
    if (overlay.lowerBound > 0) allPrices.add(overlay.lowerBound);
    if (overlay.upperBound > 0) allPrices.add(overlay.upperBound);

    final minY = allPrices.isNotEmpty ? allPrices.reduce(math.min) : 0;
    final maxY = allPrices.isNotEmpty ? allPrices.reduce(math.max) : 100;
    final yPadding = (maxY - minY) * 0.1;

    final chartData = LineChartData(
      lineBarsData: lineBarsData,
      extraLinesData: _buildExtraLines(overlay),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (value, meta) {
              if (value.toInt() == closePrices.length - 1) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: const Text('现'),
                );
              }
              if (value.toInt() == closePrices.length + futureSteps ~/ 2) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: const Text('预'),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50,
            getTitlesWidget: (value, meta) {
              if (value == meta.min) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10),
                );
              }
              if (value == meta.max) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    value.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 10),
                  );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
      minX: 0,
      maxX: maxX,
      minY: minY - yPadding,
      maxY: maxY + yPadding,
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: (maxY - minY) / 5,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: const Color(0xFFEEEEEE),
            strokeWidth: 1,
          );
        },
      ),
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (touchedSpots) {
            if (touchedSpots.isEmpty) return Colors.transparent;
            return touchedSpots.first.barIndex == 0
                ? _kLineColor.withOpacity(0.8)
                : _upColor.withOpacity(0.8);
          },
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final isPrediction = spot.barIndex == 1;
              final isSignal = spot.barIndex >= 2;
              final label = isPrediction
                  ? '预测'
                  : isSignal
                      ? (spot.barIndex - 2 < markers.length
                          ? markers[spot.barIndex - 2].isBuy
                              ? '买入'
                              : '卖出'
                          : ''
                      : '价格';
              return LineTooltipItem(
                '$label: ${spot.y.toStringAsFixed(2)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList();
          },
        ),
      ),
    );

    return ChartConfig(
      chartData: chartData,
      markers: markers,
      overlay: overlay,
      highlights: highlights,
    );
  }

  /// 生成完整图表数据（兼容旧接口）
  LineChartData buildCompleteChart({
    required PredictionOverlay overlay,
  }) {
    final config = buildChartConfig();
    return config.chartData;
  }

  /// 生成图表摘要信息
  String generateChartSummary() {
    final pred = payload.prediction;
    final trend = pred.trendProbability;
    final direction = trend.primaryDirection;
    final directionLabel = direction == 'up'
        ? '看涨'
        : direction == 'down'
            ? '看跌'
            : '震荡';

    final buf = StringBuffer();
    buf.writeln('=== 图表配置摘要 ===');
    buf.writeln('股票: ${payload.symbol}');
    buf.writeln('趋势判断: $directionLabel');
    buf.writeln('上涨概率: ${(trend.up * 100).toStringAsFixed(1)}%');
    buf.writeln('下跌概率: ${(trend.down * 100).toStringAsFixed(1)}%');
    buf.writeln('横盘概率: ${(trend.flat * 100).toStringAsFixed(1)}%');
    buf.writeln('预测收益率: ${(pred.predictedReturn * 100).toStringAsFixed(2)}%');
    buf.writeln(
        '置信区间: [${pred.confidenceInterval.lower.toStringAsFixed(2)}, ${pred.confidenceInterval.upper.toStringAsFixed(2)}]');
    buf.writeln('买入信号: ${payload.buySignals.length} 个');
    buf.writeln('卖出信号: ${payload.sellSignals.length} 个');

    final highlights = generateAttentionHighlights();
    if (highlights.isNotEmpty) {
      buf.writeln('关键时间区间:');
      for (final h in highlights) {
        buf.writeln(
            '  [${h.startIndex} - ${h.endIndex}] 强度: ${h.intensity.toStringAsFixed(3)}');
      }
    }

    return buf.toString();
  }
}

/// 自定义箭头绘制器
class FlDotCustomPainter extends FlDotPainter {
  final bool isBuy;
  final Color color;
  final double size;
  final double strength;

  FlDotCustomPainter({
    required this.isBuy,
    required this.color,
    required this.size,
    required this.strength,
  });

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas,
      double rotation, double scale) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final arrowSize = size * (0.5 + strength * 0.5);

    final path = Path();

    if (isBuy) {
      path.moveTo(offsetInCanvas.dx, offsetInCanvas.dy - arrowSize);
      path.lineTo(offsetInCanvas.dx - arrowSize * 0.6, offsetInCanvas.dy);
      path.lineTo(offsetInCanvas.dx + arrowSize * 0.6, offsetInCanvas.dy);
      path.close();
    } else {
      path.moveTo(offsetInCanvas.dx, offsetInCanvas.dy + arrowSize);
      path.lineTo(offsetInCanvas.dx - arrowSize * 0.6, offsetInCanvas.dy);
      path.lineTo(offsetInCanvas.dx + arrowSize * 0.6, offsetInCanvas.dy);
      path.close();
    }

    canvas.drawPath(path, paint);

    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, strokePaint);
  }

  @override
  Size getSize(FlSpot spot, double scale) => Size(size * 2, size * 2);

  @override
  List<Object?> get props => [isBuy, color, size, strength];
}
