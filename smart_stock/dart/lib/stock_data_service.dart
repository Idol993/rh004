/// stock_data_service.dart
/// ========================
/// 股票数据加载服务 - 统一管理本地资源加载。
///
/// 加载优先级：
///   1. 优先从 assets/demo_data/ 目录读取（后端同步的真实数据）
///   2. assets 加载失败时，自动 fallback 到内置 mock_data.dart
///   3. 任何异常都返回默认数据或空对象，确保页面不崩溃
///
/// 功能：
///   - 从 assets/demo_data/ 加载股票列表索引
///   - 加载单只股票的完整分析数据（payload + OHLCV + closePrices）
///   - 空值安全：加载失败或数据缺失时返回空对象，不崩溃
///   - 支持缓存已加载的数据，避免重复 IO
///
/// 遵循 Effective Dart 规范。

import 'dart:convert';
import 'package:flutter/services.dart';
import 'signal_models.dart';
import 'mock_data.dart';

/// 股票基本信息
class StockInfo {
  final String symbol;
  final String name;

  const StockInfo({
    required this.symbol,
    required this.name,
  });

  factory StockInfo.fromJson(Map<String, dynamic>? json) => StockInfo(
        symbol: (json?['symbol'] as String?) ?? '',
        name: (json?['name'] as String?) ?? '',
      );
}

/// 单只股票的完整数据包
class StockDataBundle {
  final String symbol;
  final String name;
  final AnalysisPayload payload;
  final List<double> closePrices;
  final List<List<double>> ohlcv;

  const StockDataBundle({
    required this.symbol,
    required this.name,
    required this.payload,
    required this.closePrices,
    required this.ohlcv,
  });

  factory StockDataBundle.empty() => StockDataBundle(
        symbol: '',
        name: '',
        payload: AnalysisPayload.empty(),
        closePrices: const [],
        ohlcv: const [],
      );

  bool get isEmpty => symbol.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

/// 内置的默认股票列表（assets 加载失败时使用）
const List<StockInfo> _kDefaultStocks = [
  StockInfo(symbol: '000001.SZ', name: '平安银行'),
  StockInfo(symbol: '600519.SH', name: '贵州茅台'),
  StockInfo(symbol: '300750.SZ', name: '宁德时代'),
  StockInfo(symbol: '601318.SH', name: '中国平安'),
];

/// 股票数据服务
class StockDataService {
  static const String _basePath = 'assets/demo_data';
  static const String _indexFile = 'index.json';

  static final StockDataService _instance = StockDataService._internal();
  factory StockDataService() => _instance;
  StockDataService._internal();

  final Map<String, StockDataBundle> _cache = {};
  List<StockInfo>? _stockList;

  /// 获取股票列表（带缓存 + fallback）
  Future<List<StockInfo>> getStockList() async {
    if (_stockList != null) return _stockList!;

    try {
      final content = await rootBundle.loadString('$_basePath/$_indexFile');
      final jsonMap = jsonDecode(content) as Map<String, dynamic>?;
      final list = (jsonMap?['symbols'] as List?)
              ?.map((e) => StockInfo.fromJson(e as Map<String, dynamic>?))
              .where((s) => s.symbol.isNotEmpty)
              .toList() ??
          [];
      if (list.isNotEmpty) {
        _stockList = list;
        return list;
      }
    } catch (_) {}

    _stockList = _kDefaultStocks;
    return _kDefaultStocks;
  }

  /// 加载单只股票数据（带缓存 + fallback）
  Future<StockDataBundle> loadStock(String symbol) async {
    if (_cache.containsKey(symbol)) {
      return _cache[symbol]!;
    }

    StockDataBundle? bundle;

    try {
      final content = await rootBundle.loadString('$_basePath/$symbol.json');
      bundle = _parseStockData(content);
    } catch (_) {
      bundle = null;
    }

    if (bundle == null || bundle.isEmpty) {
      bundle = _loadFromMockData(symbol);
    }

    _cache[symbol] = bundle;
    return bundle;
  }

  /// 从内置 mock_data 加载 fallback 数据
  StockDataBundle _loadFromMockData(String symbol) {
    try {
      final data = MockStockData.getData(symbol);
      final name = (data['name'] as String?) ?? '';

      final payloadJson = data['payload'];
      AnalysisPayload payload;
      if (payloadJson is String) {
        payload = AnalysisPayload.fromJsonString(payloadJson);
      } else if (payloadJson is Map<String, dynamic>) {
        payload = AnalysisPayload.fromJson(payloadJson);
      } else {
        payload = AnalysisPayload.empty();
      }

      final closePrices = (data['closePrices'] as List?)
              ?.map((e) => (e as num?)?.toDouble() ?? 0.0)
              .toList() ??
          const [];

      return StockDataBundle(
        symbol: symbol,
        name: name,
        payload: payload,
        closePrices: closePrices,
        ohlcv: const [],
      );
    } catch (_) {
      return StockDataBundle.empty();
    }
  }

  /// 预加载所有股票数据
  Future<List<StockDataBundle>> preloadAll() async {
    final list = await getStockList();
    final futures = list.map((info) => loadStock(info.symbol));
    final results = await Future.wait(futures);
    return results.where((b) => b.isNotEmpty).toList();
  }

  /// 清空缓存
  void clearCache() {
    _cache.clear();
    _stockList = null;
  }

  /// 解析单只股票 JSON 数据
  StockDataBundle _parseStockData(String content) {
    try {
      final jsonMap = jsonDecode(content) as Map<String, dynamic>?;
      if (jsonMap == null) return StockDataBundle.empty();

      final symbol = (jsonMap['symbol'] as String?) ?? '';
      final name = (jsonMap['name'] as String?) ?? '';

      final payloadJson = jsonMap['payload'] as Map<String, dynamic>?;
      final payload = payloadJson != null
          ? AnalysisPayload.fromJson(payloadJson)
          : AnalysisPayload.empty();

      final closePrices = (jsonMap['closePrices'] as List?)
              ?.map((e) => (e as num?)?.toDouble() ?? 0.0)
              .toList() ??
          const [];

      final ohlcvRaw = jsonMap['ohlcv'] as List?;
      final ohlcv = ohlcvRaw
              ?.map((row) {
                final rowList = row as List?;
                return rowList
                        ?.map((e) => (e as num?)?.toDouble() ?? 0.0)
                        .toList() ??
                    <double>[];
              })
              .toList() ??
          const [];

      if (symbol.isEmpty || closePrices.isEmpty) {
        return StockDataBundle.empty();
      }

      return StockDataBundle(
        symbol: symbol,
        name: name,
        payload: payload,
        closePrices: closePrices,
        ohlcv: ohlcv,
      );
    } catch (e) {
      return StockDataBundle.empty();
    }
  }
}
