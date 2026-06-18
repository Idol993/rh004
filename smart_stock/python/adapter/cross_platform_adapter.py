"""
cross_platform_adapter.py
=========================
跨端代码生成适配器 —— 打通后端推理结果到 Flutter 前端的"最后一公里"。

职责：
  1. 定义标准的 JSON Schema（趋势概率、置信区间、买卖信号坐标）。
  2. 提供 Python 端序列化逻辑，将模型输出转为 JSON。
  3. 生成 Dart 端反序列化代码片段。

JSON Schema 规范
~~~~~~~~~~~~~~~~
{
    "version": "1.0",
    "symbol": "000001.SZ",
    "timestamp": "2026-06-18T10:30:00Z",
    "prediction": {
        "trend_probability": {
            "up": 0.65,
            "down": 0.20,
            "flat": 0.15
        },
        "confidence_interval": {
            "lower": 12.30,
            "upper": 13.80,
            "level": 0.95
        },
        "predicted_return": 0.032
    },
    "signals": [
        {
            "index": 45,
            "type": "buy",
            "price": 12.50,
            "strength": 0.82
        }
    ],
    "attention_weights": [0.02, 0.01, ..., 0.15]
}
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

import numpy as np
import torch


# ======================================================================
# 数据类定义
# ======================================================================

@dataclass
class TrendProbability:
    """趋势概率。

    Attributes
    ----------
    up : float
        上涨概率 ∈ [0, 1]。
    down : float
        下跌概率 ∈ [0, 1]。
    flat : float
        横盘概率 ∈ [0, 1]。
    """
    up: float = 0.0
    down: float = 0.0
    flat: float = 0.0


@dataclass
class ConfidenceInterval:
    """置信区间。

    Attributes
    ----------
    lower : float
        下界。
    upper : float
        上界。
    level : float
        置信水平（如 0.95）。
    """
    lower: float = 0.0
    upper: float = 0.0
    level: float = 0.95


@dataclass
class PredictionResult:
    """预测结果。

    Attributes
    ----------
    trend_probability : TrendProbability
        趋势概率分布。
    confidence_interval : ConfidenceInterval
        预测价格置信区间。
    predicted_return : float
        预测收益率。
    """
    trend_probability: TrendProbability = field(default_factory=TrendProbability)
    confidence_interval: ConfidenceInterval = field(default_factory=ConfidenceInterval)
    predicted_return: float = 0.0


@dataclass
class SignalPoint:
    """买卖信号点。

    Attributes
    ----------
    index : int
        在 K 线序列中的索引位置。
    type : str
        信号类型："buy" 或 "sell"。
    price : float
        信号价格。
    strength : float
        信号强度 ∈ [0, 1]。
    """
    index: int = 0
    type: str = "buy"
    price: float = 0.0
    strength: float = 0.0


@dataclass
class AnalysisPayload:
    """端云传输的完整载荷。

    Attributes
    ----------
    version : str
        协议版本。
    symbol : str
        股票代码。
    timestamp : str
        ISO 8601 时间戳。
    prediction : PredictionResult
        预测结果。
    signals : list[SignalPoint]
        买卖信号列表。
    attention_weights : list[float]
        注意力权重（供前端可视化关键时间点）。
    """
    version: str = "1.0"
    symbol: str = ""
    timestamp: str = ""
    prediction: PredictionResult = field(default_factory=PredictionResult)
    signals: List[SignalPoint] = field(default_factory=list)
    attention_weights: List[float] = field(default_factory=list)


# ======================================================================
# 序列化器
# ======================================================================

class PayloadSerializer:
    """Python 端序列化器，将模型输出转为符合 JSON Schema 的字典/JSON 字符串。"""

    @staticmethod
    def _softmax_to_trend(raw_return: float) -> TrendProbability:
        """将原始预测收益率转化为趋势概率。

        使用类 softmax 映射：
            若 r > 0: up = sigmoid(|r|),  down = (1 - up) * 0.6,  flat = (1 - up) * 0.4
            若 r < 0: down = sigmoid(|r|), up = (1 - down) * 0.4, flat = (1 - down) * 0.6
            归一化保证 up + down + flat = 1
        """
        r = float(raw_return)
        abs_r = min(abs(r), 1.0)
        confidence = 1.0 / (1.0 + np.exp(-10 * abs_r))

        if r >= 0:
            up = confidence
            down = (1 - confidence) * 0.6
            flat = (1 - confidence) * 0.4
        else:
            down = confidence
            up = (1 - confidence) * 0.4
            flat = (1 - confidence) * 0.6

        total = up + down + flat
        return TrendProbability(
            up=round(up / total, 4),
            down=round(down / total, 4),
            flat=round(flat / total, 4),
        )

    @staticmethod
    def _compute_confidence_interval(
        predicted_return: float,
        last_close: float,
        volatility: float = 0.02,
        level: float = 0.95,
    ) -> ConfidenceInterval:
        """基于预测收益率与波动率计算置信区间。

        假设收益率服从正态分布，置信区间为：
            [S_0 * (1 + r - z * σ),  S_0 * (1 + r + z * σ)]
        其中 z = 1.96 (95% 置信水平)。
        """
        z = 1.96 if level == 0.95 else 2.576
        lower = last_close * (1 + predicted_return - z * volatility)
        upper = last_close * (1 + predicted_return + z * volatility)
        return ConfidenceInterval(
            lower=round(lower, 4),
            upper=round(upper, 4),
            level=level,
        )

    @classmethod
    def from_model_output(
        cls,
        pred_value: float,
        attention_weights: Optional[np.ndarray] = None,
        last_close: float = 0.0,
        volatility: float = 0.02,
        symbol: str = "",
    ) -> AnalysisPayload:
        """从模型原始输出构建完整载荷。

        Parameters
        ----------
        pred_value : float
            模型预测的收益率。
        attention_weights : np.ndarray, optional
            自注意力权重向量。
        last_close : float
            最新收盘价（用于计算置信区间）。
        volatility : float
            近期波动率估计。
        symbol : str
            股票代码。

        Returns
        -------
        AnalysisPayload
        """
        trend_prob = cls._softmax_to_trend(pred_value)
        ci = cls._compute_confidence_interval(pred_value, last_close, volatility)
        prediction = PredictionResult(
            trend_probability=trend_prob,
            confidence_interval=ci,
            predicted_return=round(pred_value, 6),
        )
        attn_list = []
        if attention_weights is not None:
            attn_list = [round(float(w), 6) for w in attention_weights]

        return AnalysisPayload(
            symbol=symbol,
            timestamp=datetime.now(timezone.utc).isoformat(),
            prediction=prediction,
            attention_weights=attn_list,
        )

    @staticmethod
    def add_signals(
        payload: AnalysisPayload,
        close_prices: np.ndarray,
        strength_threshold: float = 0.6,
    ) -> AnalysisPayload:
        """根据趋势概率和价格序列，生成买卖信号点。

        信号生成规则：
          - 当趋势上涨概率 > threshold 且当前处于局部低点 → buy
          - 当趋势下跌概率 > threshold 且当前处于局部高点 → sell

        Parameters
        ----------
        payload : AnalysisPayload
            已有载荷。
        close_prices : np.ndarray
            收盘价序列。
        strength_threshold : float
            信号触发阈值。
        """
        trend = payload.prediction.trend_probability
        n = len(close_prices)
        signals: List[SignalPoint] = []

        for i in range(2, n):
            is_local_min = (
                close_prices[i - 1] < close_prices[i - 2]
                and close_prices[i - 1] < close_prices[i]
            )
            is_local_max = (
                close_prices[i - 1] > close_prices[i - 2]
                and close_prices[i - 1] > close_prices[i]
            )

            if trend.up > strength_threshold and is_local_min:
                signals.append(
                    SignalPoint(
                        index=i - 1,
                        type="buy",
                        price=round(float(close_prices[i - 1]), 4),
                        strength=round(trend.up, 4),
                    )
                )
            elif trend.down > strength_threshold and is_local_max:
                signals.append(
                    SignalPoint(
                        index=i - 1,
                        type="sell",
                        price=round(float(close_prices[i - 1]), 4),
                        strength=round(trend.down, 4),
                    )
                )

        payload.signals = signals
        return payload

    @staticmethod
    def to_json(payload: AnalysisPayload) -> str:
        """序列化为 JSON 字符串。"""
        return json.dumps(asdict(payload), ensure_ascii=False, indent=2)

    @staticmethod
    def to_dict(payload: AnalysisPayload) -> Dict[str, Any]:
        """序列化为字典。"""
        return asdict(payload)


# ======================================================================
# Dart 代码生成器
# ======================================================================

class DartCodeGenerator:
    """根据 JSON Schema 生成 Dart 反序列化代码片段。"""

    @staticmethod
    def generate_dart_models() -> str:
        """生成 Dart 数据模型代码（供参考/复制到 Flutter 项目）。"""
        return '''
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

  factory TrendProbability.fromJson(Map<String, dynamic> json) =>
      TrendProbability(
        up: (json['up'] as num).toDouble(),
        down: (json['down'] as num).toDouble(),
        flat: (json['flat'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'up': up, 'down': down, 'flat': flat};
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
            TrendProbability.fromJson(json['trend_probability']),
        confidenceInterval:
            ConfidenceInterval.fromJson(json['confidence_interval']),
        predictedReturn: (json['predicted_return'] as num).toDouble(),
      );
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
        prediction: PredictionResult.fromJson(json['prediction']),
        signals: (json['signals'] as List)
            .map((e) => SignalPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        attentionWeights: (json['attention_weights'] as List)
            .map((e) => (e as num).toDouble())
            .toList(),
      );

  factory AnalysisPayload.fromJsonString(String str) =>
      AnalysisPayload.fromJson(jsonDecode(str) as Map<String, dynamic>);
}
'''
