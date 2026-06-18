"""
generate_demo_data.py
=====================
生成联调验收用的完整演示数据。

生成 4 只股票的分析结果，包含：
  - 完整的趋势概率、置信区间、预测收益率
  - 80 条 OHLCV 数据
  - 买卖信号点坐标
  - 60 个注意力权重值

所有 JSON 保存到 demo_data/ 目录，供 Dart 端直接加载使用。
"""

from __future__ import annotations

import json
import os
import numpy as np
import sys

sys.path.insert(0, os.path.dirname(__file__))

from pipeline.market_data_pipeline import MarketDataPipeline
from adapter.cross_platform_adapter import (
    AnalysisPayload,
    PayloadSerializer,
    SignalPoint,
    TrendProbability,
    ConfidenceInterval,
    PredictionResult,
)


def generate_ohlcv(
    n_bars: int = 80,
    start_price: float = 100.0,
    trend: float = 0.0,
    volatility: float = 0.02,
    seed: int = 42,
) -> np.ndarray:
    """生成模拟 OHLCV 数据。

    使用几何布朗运动：
        S_{t+1} = S_t * exp((μ - σ²/2) * Δt + σ * √Δt * Z_t)
    """
    rng = np.random.default_rng(seed)
    dt = 1.0
    close = [start_price]
    for _ in range(n_bars - 1):
        z = rng.standard_normal()
        drift = (trend - 0.5 * volatility ** 2) * dt
        diffusion = volatility * np.sqrt(dt) * z
        close.append(close[-1] * np.exp(drift + diffusion))

    close = np.array(close)
    noise = rng.uniform(0.001, 0.015, size=n_bars)
    high = close * (1 + noise)
    low = close * (1 - noise)
    open_ = close * (1 + rng.uniform(-0.01, 0.01, size=n_bars))
    volume = rng.uniform(1e6, 5e6, size=n_bars)

    return np.column_stack([open_, high, low, close, volume])


def generate_attention_weights(
    length: int = 60,
    peak_positions: list[int] | None = None,
) -> np.ndarray:
    """生成带峰值的注意力权重。

    在指定位置生成高斯分布的峰值，模拟模型关注的关键时间点。
    """
    weights = np.full(length, 0.01)
    if peak_positions is None:
        peak_positions = [length // 3, 2 * length // 3]

    for peak in peak_positions:
        for i in range(length):
            distance = abs(i - peak)
            if distance < 10:
                weights[i] += 0.12 * (1 - distance / 10)

    return weights / weights.sum()


def generate_payload(
    symbol: str,
    pred_return: float,
    close_prices: np.ndarray,
    peak_positions: list[int],
    signals: list[SignalPoint],
    volatility: float = 0.02,
) -> AnalysisPayload:
    """生成完整的 AnalysisPayload。"""
    attn = generate_attention_weights(peak_positions=peak_positions)
    payload = PayloadSerializer.from_model_output(
        pred_value=pred_return,
        attention_weights=attn,
        last_close=close_prices[-1],
        volatility=volatility,
        symbol=symbol,
    )
    payload.signals = signals
    return payload


def generate_all_demo_data(output_dir: str = "demo_data") -> None:
    """生成所有演示数据并保存到 JSON 文件。"""
    os.makedirs(output_dir, exist_ok=True)

    demo_configs = [
        {
            "symbol": "000001.SZ",
            "name": "平安银行",
            "start_price": 10.5,
            "trend": 0.0008,
            "volatility": 0.015,
            "pred_return": 0.0285,
            "peak_positions": [20, 45, 70],
            "signals": [
                SignalPoint(index=15, type="buy", price=10.42, strength=0.75),
                SignalPoint(index=38, type="buy", price=10.68, strength=0.68),
                SignalPoint(index=62, type="buy", price=10.89, strength=0.72),
            ],
        },
        {
            "symbol": "600519.SH",
            "name": "贵州茅台",
            "start_price": 1680.0,
            "trend": -0.0012,
            "volatility": 0.02,
            "pred_return": -0.035,
            "peak_positions": [30, 60],
            "signals": [
                SignalPoint(index=22, type="sell", price=1685.0, strength=0.70),
                SignalPoint(index=55, type="sell", price=1655.0, strength=0.65),
            ],
        },
        {
            "symbol": "300750.SZ",
            "name": "宁德时代",
            "start_price": 185.0,
            "trend": 0.0,
            "volatility": 0.025,
            "pred_return": 0.005,
            "peak_positions": [15, 35, 55, 75],
            "signals": [],
        },
        {
            "symbol": "601318.SH",
            "name": "中国平安",
            "start_price": 45.0,
            "trend": 0.0005,
            "volatility": 0.018,
            "pred_return": 0.018,
            "peak_positions": [10, 32, 50, 68],
            "signals": [
                SignalPoint(index=28, type="sell", price=45.8, strength=0.62),
                SignalPoint(index=58, type="buy", price=44.9, strength=0.58),
            ],
        },
    ]

    all_data = {}

    for i, config in enumerate(demo_configs):
        print(f"[Generating] {config['symbol']} ({config['name']}) ...")

        ohlcv = generate_ohlcv(
            n_bars=80,
            start_price=config["start_price"],
            trend=config["trend"],
            volatility=config["volatility"],
            seed=42 + i * 100,
        )

        close_prices = ohlcv[:, 3]

        payload = generate_payload(
            symbol=config["symbol"],
            pred_return=config["pred_return"],
            close_prices=close_prices,
            peak_positions=config["peak_positions"],
            signals=config["signals"],
            volatility=config["volatility"],
        )

        payload_dict = PayloadSerializer.to_dict(payload)

        data = {
            "symbol": config["symbol"],
            "name": config["name"],
            "payload": payload_dict,
            "payload_json": json.dumps(payload_dict, ensure_ascii=False, indent=2),
            "ohlcv": ohlcv.tolist(),
            "closePrices": close_prices.tolist(),
            "columns": ["open", "high", "low", "close", "volume"],
        }

        all_data[config["symbol"]] = data

        symbol_file = os.path.join(output_dir, f"{config['symbol']}.json")
        with open(symbol_file, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"  已保存: {symbol_file}")

    index_file = os.path.join(output_dir, "index.json")
    with open(index_file, "w", encoding="utf-8") as f:
        json.dump(
            {
                "symbols": [
                    {"symbol": c["symbol"], "name": c["name"]} for c in demo_configs
                ],
                "timestamp": "2026-06-18T10:30:00Z",
                "version": "1.0",
            },
            f,
            ensure_ascii=False,
            indent=2,
        )
    print(f"[Index] 已保存: {index_file}")

    print("\n" + "=" * 70)
    print("  演示数据生成完成！")
    print("=" * 70)
    for config in demo_configs:
        d = all_data[config["symbol"]]
        p = d["payload"]
        print(f"\n【{config['symbol']} - {config['name']}】")
        print(f"  趋势: up={p['prediction']['trend_probability']['up']:.2%}, "
              f"down={p['prediction']['trend_probability']['down']:.2%}, "
              f"flat={p['prediction']['trend_probability']['flat']:.2%}")
        print(f"  预测收益率: {p['prediction']['predicted_return']:.4%}")
        print(f"  置信区间: [{p['prediction']['confidence_interval']['lower']:.2f}, "
              f"{p['prediction']['confidence_interval']['upper']:.2f}]")
        print(f"  信号数量: {len(p['signals'])}")
        for s in p['signals']:
            print(f"    - {s['type']} @ 位置#{s['index']}, 价格¥{s['price']:.2f}, 强度{s['strength']:.2%}")
        print(f"  注意力权重: {len(p['attention_weights'])} 个")


def main() -> None:
    output_dir = os.path.join(os.path.dirname(__file__), "demo_data")
    generate_all_demo_data(output_dir)

    # 同时生成一份给 Dart 端的 mock_data.dart 格式
    print("\n" + "=" * 70)
    print("  Dart 端使用说明")
    print("=" * 70)
    print("""
    demo_data/ 目录下的 JSON 文件可直接用于 Flutter 端：

    1. 将 demo_data/ 复制到 Flutter 项目的 assets/ 目录
    2. 在 pubspec.yaml 中声明：
        assets:
          - assets/demo_data/

    3. 运行时加载：
        final data = await rootBundle.loadString('assets/demo_data/000001.SZ.json');
        final payload = AnalysisPayload.fromJsonString(jsonDecode(data)['payload_json']);
    """)


if __name__ == "__main__":
    main()
