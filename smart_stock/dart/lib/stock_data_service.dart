/// stock_data_service.dart
/// ========================
/// 股票数据加载服务 - 统一管理本地 assets 资源加载。
///
/// 功能：
///   1. 从 assets/demo_data/ 加载股票列表索引
///   2. 加载单只股票的完整分析数据（payload + OHLCV）
///   3. 空值安全：加载失败或数据缺失时返回空对象，不崩溃
///   4. 支持缓存已加载的数据，避免重复 IO
///
/// 遵循 Effective Dart 规范。

import 'dart:convert';
import 'package:flutter/services.dart';
import 'signal_models.dart';

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

/// 股票数据服务
class StockDataService {
  static const String _basePath = 'assets/demo_data';
  static const String _indexFile = 'index.json';

  static final StockDataService _instance = StockDataService._internal();
  factory StockDataService() => _instance;
  StockDataService._internal();

  final Map<String, StockDataBundle> _cache = {};
  List<StockInfo>? _stockList;

  /// 获取股票列表（带缓存）
  Future<List<StockInfo>> getStockList() async {
    if (_stockList != null) return _stockList!;

    try {
      final content = await rootBundle.loadString('$_basePath/$_indexFile');
      final jsonMap = jsonDecode(content) as Map<String, dynamic>?;
      final list = (jsonMap?['symbols'] as List?)
              ?.map((e) => StockInfo.fromJson(e as Map<String, dynamic>?))
              .toList() ??
          [];
      _stockList = list;
      return list;
    } catch (e) {
      return const [];
    }
  }

  /// 加载单只股票数据（带缓存）
  Future<StockDataBundle> loadStock(String symbol) async {
    if (_cache.containsKey(symbol)) {
      return _cache[symbol]!;
    }

    try {
      final content = await rootBundle.loadString('$_basePath/$symbol.json');
      final bundle = _parseStockData(content);
      _cache[symbol] = bundle;
      return bundle;
    } catch (e) {
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
