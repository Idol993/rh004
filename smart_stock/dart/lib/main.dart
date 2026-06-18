/// main.dart
/// ==========
/// 端云协同智能炒股分析系统 - Flutter 应用入口。

import 'package:flutter/material.dart';
import 'stock_chart_page.dart';

void main() {
  runApp(const StockAnalysisApp());
}

class StockAnalysisApp extends StatelessWidget {
  const StockAnalysisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '端云协同智能炒股分析',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const StockChartPage(),
    );
  }
}
