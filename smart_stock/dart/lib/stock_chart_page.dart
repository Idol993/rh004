/// stock_chart_page.dart
/// =====================
/// 端云协同智能炒股分析系统 - Flutter 图表页面。
///
/// 功能：
///   1. 切换不同股票，触发数据刷新
///   2. 展示 K 线图 + 买卖信号箭头 + 趋势预测虚线 + 置信区间
///   3. 面板展示预测概率、置信区间、买卖点列表
///   4. 注意力权重热力图展示关键时间点
///
/// 遵循 Effective Dart 规范。

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'signal_models.dart';
import 'chart_config_generator.dart';
import 'mock_data.dart';

class StockChartPage extends StatefulWidget {
  const StockChartPage({super.key});

  @override
  State<StockChartPage> createState() => _StockChartPageState();
}

class _StockChartPageState extends State<StockChartPage> {
  final List<String> _symbols = const [
    '000001.SZ',
    '600519.SH',
    '300750.SZ',
    '601318.SH',
  ];

  String _currentSymbol = '000001.SZ';
  AnalysisPayload _payload = AnalysisPayload.empty();
  List<double> _closePrices = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStockData();
  }

  Future<void> _loadStockData() async {
    setState(() {
      _isLoading = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 500));

    final data = MockStockData.getData(_currentSymbol);
    setState(() {
      _payload = AnalysisPayload.fromJsonString(data['payload'] as String);
      _closePrices = List<double>.from(data['closePrices'] as List);
      _isLoading = false;
    });
  }

  void _onSymbolChanged(String? symbol) {
    if (symbol != null && symbol != _currentSymbol) {
      _currentSymbol = symbol;
      _loadStockData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('端云协同智能炒股分析系统'),
        elevation: 2,
      ),
      body: Column(
        children: [
          _buildSymbolSelector(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _payload.isEmpty
                    ? const Center(child: Text('暂无数据'))
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildSymbolSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[50],
      child: Row(
        children: [
          const Text(
            '股票选择: ',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          DropdownButton<String>(
            value: _currentSymbol,
            items: _symbols
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: _onSymbolChanged,
          ),
          const Spacer(),
          if (_payload.timestamp.isNotEmpty)
            Text(
              '更新时间: ${_formatTimestamp(_payload.timestamp)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPredictionCard(),
          const SizedBox(height: 16),
          _buildChartCard(),
          const SizedBox(height: 16),
          _buildSignalsCard(),
          const SizedBox(height: 16),
          _buildAttentionCard(),
        ],
      ),
    );
  }

  Widget _buildPredictionCard() {
    final pred = _payload.prediction;
    final trend = pred.trendProbability;
    final direction = trend.primaryDirection;
    final directionLabel = direction == 'up'
        ? '看涨'
        : direction == 'down'
            ? '看跌'
            : '震荡';
    final directionColor = direction == 'up'
        ? Colors.green
        : direction == 'down'
            ? Colors.red
            : Colors.orange;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: directionColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    directionLabel,
                    style: TextStyle(
                      color: directionColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '预测收益率: ${(pred.predictedReturn * 100).toStringAsFixed(2)}%',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '趋势概率分布',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _buildProbabilityBar('上涨', trend.up, Colors.green),
            const SizedBox(height: 4),
            _buildProbabilityBar('下跌', trend.down, Colors.red),
            const SizedBox(height: 4),
            _buildProbabilityBar('横盘', trend.flat, Colors.orange),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    '置信区间下限',
                    pred.confidenceInterval.lower.toStringAsFixed(2),
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoBox(
                    '置信区间上限',
                    pred.confidenceInterval.upper.toStringAsFixed(2),
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoBox(
                    '置信水平',
                    '${(pred.confidenceInterval.level * 100).toInt()}%',
                    Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProbabilityBar(String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              FractionallySizedBox(
                widthFactor: value,
                child: Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text(
            '${(value * 100).toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    final generator = ChartConfigGenerator(
      payload: _payload,
      closePrices: _closePrices,
    );
    final config = generator.buildChartConfig();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '价格走势与预测',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                Row(
                  children: [
                    _buildLegendItem('收盘价', const Color(0xFF2196F3)),
                    const SizedBox(width: 12),
                    _buildLegendItem('预测趋势', const Color(0xFF4CAF50), dashed: true),
                    const SizedBox(width: 12),
                    _buildLegendItem('买入', Colors.green),
                    const SizedBox(width: 12),
                    _buildLegendItem('卖出', Colors.red),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: LineChart(config.chartData),
            ),
            const SizedBox(height: 8),
            Text(
              generator.generateChartSummary(),
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, {bool dashed = false}) {
    return Row(
      children: [
        if (dashed)
          Container(
            width: 16,
            height: 2,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: color, width: 2, style: BorderStyle.solid),
              ),
            ),
            child: const Text('  ', style: TextStyle(decoration: TextDecoration.lineThrough)),
          )
        else
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildSignalsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '买卖信号',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '共 ${_payload.signals.length} 个',
                    style: TextStyle(color: Colors.blue[700], fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_payload.signals.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('暂无信号', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              SizedBox(
                height: 150,
                child: ListView.separated(
                  itemCount: _payload.signals.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final signal = _payload.signals[index];
                    return ListTile(
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: signal.isBuy
                              ? Colors.green[50]
                              : Colors.red[50],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          signal.isBuy
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: signal.isBuy ? Colors.green : Colors.red,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        signal.isBuy ? '买入信号' : '卖出信号',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: signal.isBuy ? Colors.green : Colors.red,
                        ),
                      ),
                      subtitle: Text(
                        '位置: #${signal.index} · 强度: ${(signal.strength * 100).toStringAsFixed(0)}%',
                      ),
                      trailing: Text(
                        '¥${signal.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttentionCard() {
    final highlights = ChartConfigGenerator(
      payload: _payload,
      closePrices: _closePrices,
    ).generateAttentionHighlights();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '注意力权重热力图（关键时间点）',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (_payload.attentionWeights.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('暂无注意力数据', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Column(
                children: [
                  _buildAttentionHeatmap(),
                  const SizedBox(height: 12),
                  if (highlights.isNotEmpty) ...[
                    const Text(
                      '关键区间',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: highlights
                          .map((h) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.yellow[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '[${h.startIndex}-${h.endIndex}] 强度: ${(h.intensity * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    color: Colors.yellow[800],
                                    fontSize: 12,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttentionHeatmap() {
    final weights = _payload.attentionWeights;
    final maxW = weights.reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 30,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / weights.length;
          return Row(
            children: List.generate(weights.length, (index) {
              final normalized = weights[index] / (maxW + 1e-10);
              final color = Color.lerp(
                Colors.blue[50],
                Colors.deepOrange[400],
                normalized,
              )!;
              return Container(
                width: itemWidth,
                color: color,
              );
            }),
          );
        },
      ),
    );
  }

  String _formatTimestamp(String ts) {
    try {
      final dt = DateTime.parse(ts).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts;
    }
  }
}
