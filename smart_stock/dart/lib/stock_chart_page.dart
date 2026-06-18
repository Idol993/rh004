/// stock_chart_page.dart
/// =====================
/// 端云协同智能炒股分析系统 - Flutter 图表页面。
///
/// 功能：
///   1. 从本地 assets 加载股票列表和分析数据
///   2. 切换不同股票，K线/预测/信号/注意力全部联动刷新
///   3. 展示预测概率、置信区间、买卖点列表、注意力热力图
///   4. 空数据友好展示，不崩溃
///
/// 遵循 Effective Dart 规范。

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'signal_models.dart';
import 'chart_config_generator.dart';
import 'stock_data_service.dart';

class StockChartPage extends StatefulWidget {
  const StockChartPage({super.key});

  @override
  State<StockChartPage> createState() => _StockChartPageState();
}

class _StockChartPageState extends State<StockChartPage> {
  final StockDataService _dataService = StockDataService();

  List<StockInfo> _stockList = [];
  String _currentSymbol = '';
  StockDataBundle _currentData = StockDataBundle.empty();
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _dataService.getStockList();
      if (list.isEmpty) {
        setState(() {
          _stockList = [];
          _isLoading = false;
          _errorMessage = '未找到股票数据';
        });
        return;
      }

      setState(() {
        _stockList = list;
        _currentSymbol = list.first.symbol;
      });

      await _loadStockData(list.first.symbol);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载失败: ${e.toString().substring(0, 50)}';
      });
    }
  }

  Future<void> _loadStockData(String symbol) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _dataService.loadStock(symbol);
      setState(() {
        _currentData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载 ${symbol} 失败';
      });
    }
  }

  void _onSymbolChanged(String? symbol) {
    if (symbol != null && symbol != _currentSymbol) {
      setState(() => _currentSymbol = symbol);
      _loadStockData(symbol);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('端云协同智能炒股分析'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initData,
            tooltip: '刷新数据',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSymbolSelector(),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildSymbolSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.show_chart, size: 20, color: Colors.blue),
          const SizedBox(width: 8),
          const Text(
            '股票: ',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          DropdownButton<String>(
            value: _currentSymbol.isEmpty ? null : _currentSymbol,
            items: _stockList
                .map((s) => DropdownMenuItem(
                      value: s.symbol,
                      child: Text('${s.symbol}  ${s.name}'),
                    ))
                .toList(),
            onChanged: _isLoading ? null : _onSymbolChanged,
            underline: const SizedBox.shrink(),
          ),
          const Spacer(),
          if (_currentData.timestamp.isNotEmpty)
            Text(
              _formatTimestamp(_currentData.payload.timestamp),
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('加载中...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_currentData.isEmpty) {
      return _buildEmptyState();
    }

    return _buildContent();
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(_errorMessage ?? '未知错误'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _initData,
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            '暂无分析数据',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            '请检查 assets/demo_data/ 目录',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
    final payload = _currentData.payload;
    final pred = payload.prediction;
    final trend = pred.trendProbability;
    final direction = trend.primaryDirection;

    final directionLabel = switch (direction) {
      'up' => '看涨',
      'down' => '看跌',
      _ => '震荡',
    };
    final directionColor = switch (direction) {
      'up' => Colors.green,
      'down' => Colors.red,
      _ => Colors.orange,
    };

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: directionColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        direction == 'up'
                            ? Icons.trending_up
                            : direction == 'down'
                                ? Icons.trending_down
                                : Icons.trending_flat,
                        color: directionColor,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        directionLabel,
                        style: TextStyle(
                          color: directionColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '预测收益率',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${(pred.predictedReturn * 100).toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: pred.predictedReturn >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '趋势概率分布',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            _buildProbabilityBar('上涨', trend.up, Colors.green),
            const SizedBox(height: 6),
            _buildProbabilityBar('下跌', trend.down, Colors.red),
            const SizedBox(height: 6),
            _buildProbabilityBar('横盘', trend.flat, Colors.orange),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    icon: Icons.arrow_downward,
                    label: '置信下限',
                    value: pred.confidenceInterval.lower.toStringAsFixed(2),
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoBox(
                    icon: Icons.arrow_upward,
                    label: '置信上限',
                    value: pred.confidenceInterval.upper.toStringAsFixed(2),
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoBox(
                    icon: Icons.verified_outlined,
                    label: '置信水平',
                    value: '${(pred.confidenceInterval.level * 100).toInt()}%',
                    color: Colors.blue,
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
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withOpacity(0.6), color],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            '${(value * 100).toStringAsFixed(1)}%',
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        border: Border.all(color: color.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11),
          ),
          const SizedBox(height: 2),
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
    final payload = _currentData.payload;
    final closePrices = _currentData.closePrices;
    final generator = ChartConfigGenerator(
      payload: payload,
      closePrices: closePrices,
    );
    final config = generator.buildChartConfig();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  '价格走势与预测',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildLegendRow(),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: closePrices.isEmpty
                  ? _buildChartEmptyState()
                  : LineChart(config.chartData),
            ),
            const SizedBox(height: 8),
            Text(
              generator.generateChartSummary(),
              style: TextStyle(color: Colors.grey[600], fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendRow() {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _buildLegendItem('收盘价', const Color(0xFF2196F3)),
        _buildLegendItem('预测趋势', const Color(0xFF4CAF50), dashed: true),
        _buildLegendItem('买入信号', Colors.green, isArrow: true, isUp: true),
        _buildLegendItem('卖出信号', Colors.red, isArrow: true, isUp: false),
        _buildLegendItem('注意力区', Colors.yellow[700]!, isHighlight: true),
      ],
    );
  }

  Widget _buildLegendItem(
    String label,
    Color color, {
    bool dashed = false,
    bool isArrow = false,
    bool isUp = true,
    bool isHighlight = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isHighlight)
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          )
        else if (isArrow)
          Icon(
            isUp ? Icons.arrow_upward : Icons.arrow_downward,
            color: color,
            size: 14,
          )
        else if (dashed)
          SizedBox(
            width: 16,
            child: CustomPaint(
              painter: _DashedLinePainter(color: color),
              size: const Size(16, 2),
            ),
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
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildChartEmptyState() {
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.show_chart, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 8),
          const Text('暂无价格数据', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSignalsCard() {
    final signals = _currentData.payload.signals;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined,
                    size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '买卖信号',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '共 ${signals.length} 个',
                    style: TextStyle(color: Colors.blue[700], fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (signals.isEmpty)
              _buildEmptySignals()
            else
              SizedBox(
                height: 150,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: signals.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1, color: Colors.grey[200]),
                  itemBuilder: (context, index) {
                    final signal = signals[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: signal.isBuy
                              ? Colors.green[50]
                              : Colors.red[50],
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(
                          signal.isBuy
                              ? Icons.arrow_circle_up
                              : Icons.arrow_circle_down,
                          color: signal.isBuy ? Colors.green : Colors.red,
                          size: 24,
                        ),
                      ),
                      title: Text(
                        signal.isBuy ? '买入信号' : '卖出信号',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: signal.isBuy ? Colors.green : Colors.red,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '位置 #${signal.index} · 强度 ${(signal.strength * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 12),
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

  Widget _buildEmptySignals() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.check_circle_outline, size: 36, color: Colors.grey[400]),
          const SizedBox(height: 8),
          const Text(
            '当前无买卖信号',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            '请等待趋势确认后再操作',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionCard() {
    final weights = _currentData.payload.attentionWeights;
    final generator = ChartConfigGenerator(
      payload: _currentData.payload,
      closePrices: _currentData.closePrices,
    );
    final highlights = generator.generateAttentionHighlights();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.heat_pump_outlined, size: 20, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text(
                  '注意力权重',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                SizedBox(width: 8),
                Text(
                  '模型关注的关键时间点',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (weights.isEmpty)
              _buildEmptyAttention()
            else
              Column(
                children: [
                  _buildAttentionHeatmap(weights),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('低',
                          style:
                              TextStyle(fontSize: 10, color: Colors.grey[500])),
                      Text('注意力强度',
                          style:
                              TextStyle(fontSize: 10, color: Colors.grey[500])),
                      Text('高',
                          style:
                              TextStyle(fontSize: 10, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (highlights.isNotEmpty) ...[
                    const Text(
                      '关键区间',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: highlights
                          .map((h) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.amber[50],
                                  border: Border.all(
                                      color: Colors.amber[300]!),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star,
                                        size: 14, color: Colors.amber[700]),
                                    const SizedBox(width: 4),
                                    Text(
                                      '[${h.startIndex}-${h.endIndex}]  强度 ${(h.intensity * 100).toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        color: Colors.amber[800],
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
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

  Widget _buildEmptyAttention() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.visibility_off_outlined,
              size: 36, color: Colors.grey[400]),
          const SizedBox(height: 8),
          const Text(
            '暂无注意力数据',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionHeatmap(List<double> weights) {
    final maxW = weights.reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 36,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / weights.length;
            return Row(
              children: List.generate(weights.length, (index) {
                final normalized =
                    weights[index] / (maxW + 1e-10);
                final color = Color.lerp(
                  Colors.blue[50]!,
                  Colors.deepOrange[400]!,
                  normalized.clamp(0.0, 1.0),
                )!;
                return Container(
                  width: itemWidth,
                  color: color,
                );
              }),
            );
          },
        ),
      ),
    );
  }

  String _formatTimestamp(String ts) {
    try {
      if (ts.isEmpty) return '';
      final dt = DateTime.parse(ts).toLocal();
      return '更新 ${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts;
    }
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;

    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(startX + dashWidth, size.height / 2),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
