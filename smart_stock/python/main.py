"""
main.py
=======
端云协同智能炒股分析系统 —— 闭环演示流程。

演示从"加载假数据"到"生成 Flutter 配置代码"的完整闭环：
  1. 生成模拟 OHLCV 数据
  2. 通过 MarketDataPipeline 进行特征工程
  3. 使用 HybridTrendNet 进行推理
  4. 通过 PayloadSerializer 序列化结果
  5. 输出 JSON 与 Dart 代码片段
"""

from __future__ import annotations

import sys
import os
import numpy as np
import pandas as pd
import torch

sys.path.insert(0, os.path.dirname(__file__))

from pipeline.market_data_pipeline import MarketDataPipeline
from model.hybrid_trend_net import HybridTrendNet, TrendReversalLoss, ModelExporter
from adapter.cross_platform_adapter import PayloadSerializer, DartCodeGenerator


def generate_mock_ohlcv(n_bars: int = 300, seed: int = 42) -> pd.DataFrame:
    """生成模拟 OHLCV 数据。

    使用带漂移的几何布朗运动模拟价格路径：
        S_{t+1} = S_t * exp((μ - σ²/2) * Δt + σ * √Δt * Z_t)
    其中 Z_t ~ N(0, 1)。

    Parameters
    ----------
    n_bars : int
        K 线数量。
    seed : int
        随机种子。

    Returns
    -------
    pd.DataFrame
        包含 open / high / low / close / volume 列。
    """
    rng = np.random.default_rng(seed)
    mu = 0.0005
    sigma = 0.02
    dt = 1.0

    close = [100.0]
    for _ in range(n_bars - 1):
        z = rng.standard_normal()
        drift = (mu - 0.5 * sigma ** 2) * dt
        diffusion = sigma * np.sqrt(dt) * z
        close.append(close[-1] * np.exp(drift + diffusion))

    close = np.array(close)
    noise = rng.uniform(0.001, 0.015, size=n_bars)

    df = pd.DataFrame({
        "open": close * (1 + rng.uniform(-0.01, 0.01, size=n_bars)),
        "high": close * (1 + noise),
        "low": close * (1 - noise),
        "close": close,
        "volume": rng.uniform(1e6, 5e6, size=n_bars).astype(int).astype(float),
    })

    return df


def main() -> None:
    print("=" * 70)
    print("  端云协同智能炒股分析系统 —— 闭环演示")
    print("=" * 70)

    # ── Step 1: 加载模拟数据 ──────────────────────────────────────────
    print("\n[Step 1] 生成模拟 OHLCV 数据 (300 bars) ...")
    df = generate_mock_ohlcv(n_bars=300)
    print(f"  数据形状: {df.shape}")
    print(f"  收盘价范围: [{df['close'].min():.2f}, {df['close'].max():.2f}]")

    # ── Step 2: 特征工程管道 ──────────────────────────────────────────
    print("\n[Step 2] 运行 MarketDataPipeline ...")
    pipeline = MarketDataPipeline(
        window_size=60,
        zscore_window=60,
        ewma_span=20,
        iqr_multiplier=1.5,
        step=1,
    )
    tensor_data = pipeline.fit_transform(df)
    print(f"  特征维度: {len(pipeline.feature_names)}")
    print(f"  特征列表: {pipeline.feature_names[:8]} ... (共 {len(pipeline.feature_names)} 个)")
    print(f"  输出张量形状: {tensor_data.shape}")
    print(f"    → [Batch={tensor_data.shape[0]}, Time_Steps={tensor_data.shape[1]}, Features={tensor_data.shape[2]}]")

    # ── Step 3: 构建模型并推理 ────────────────────────────────────────
    print("\n[Step 3] 构建 HybridTrendNet 并推理 ...")
    input_dim = tensor_data.shape[2]
    model = HybridTrendNet(
        input_dim=input_dim,
        lstm_hidden=64,
        lstm_layers=2,
        n_heads=4,
        n_transformer_layers=2,
        d_ff=128,
        output_dim=1,
        dropout=0.1,
    )
    model.eval()

    with torch.no_grad():
        output = model(tensor_data, return_attention=True)
        pred = output["pred"]
        attn_weights = output["attn_weights"]

    print(f"  模型参数量: {sum(p.numel() for p in model.parameters()):,}")
    print(f"  预测值范围: [{pred.min().item():.6f}, {pred.max().item():.6f}]")

    # ── Step 4: 损失函数演示 ──────────────────────────────────────────
    print("\n[Step 4] TrendReversalLoss 损失函数演示 ...")
    loss_fn = TrendReversalLoss(lambda_penalty=2.0, base_loss="mse")

    dummy_true = torch.tensor([0.05, -0.03, 0.02, -0.01])
    dummy_pred = torch.tensor([0.04, 0.02, -0.01, -0.02])
    loss = loss_fn(dummy_pred, dummy_true)
    print(f"  示例 y_true: {dummy_true.tolist()}")
    print(f"  示例 y_pred: {dummy_pred.tolist()}")
    print(f"  损失值 (含趋势反转惩罚): {loss.item():.6f}")

    # ── Step 5: 序列化为 JSON ─────────────────────────────────────────
    print("\n[Step 5] 序列化推理结果为 JSON ...")
    last_sample_pred = pred[-1].item()
    last_attn = attn_weights[-1].mean(dim=0).numpy()
    if last_attn.ndim == 0:
        last_attn = attn_weights[-1, -1, :].numpy()

    payload = PayloadSerializer.from_model_output(
        pred_value=last_sample_pred,
        attention_weights=last_attn,
        last_close=df["close"].iloc[-1],
        volatility=0.02,
        symbol="000001.SZ",
    )

    close_array = df["close"].values[-80:]
    payload = PayloadSerializer.add_signals(payload, close_array)

    json_str = PayloadSerializer.to_json(payload)
    print(f"  股票: {payload.symbol}")
    print(f"  趋势概率: up={payload.prediction.trend_probability.up:.2%}, "
          f"down={payload.prediction.trend_probability.down:.2%}")
    print(f"  预测收益率: {payload.prediction.predicted_return:.4%}")
    print(f"  置信区间: [{payload.prediction.confidence_interval.lower:.2f}, "
          f"{payload.prediction.confidence_interval.upper:.2f}]")
    print(f"  买卖信号: {len(payload.signals)} 个")

    # ── Step 6: 模型导出 ─────────────────────────────────────────────
    print("\n[Step 6] 模型轻量化导出 ...")
    print("  [6a] 导出 ONNX ...")
    onnx_path = os.path.join(os.path.dirname(__file__), "hybrid_trend_net.onnx")
    try:
        ModelExporter.export_onnx(
            model, input_dim=input_dim, time_steps=60, onnx_path=onnx_path
        )
        print(f"  ONNX 模型已保存: {onnx_path}")
    except Exception as e:
        print(f"  ONNX 导出跳过 (需安装 onnx): {e}")

    print("  [6b] 动态 INT8 量化 ...")
    try:
        quantized = ModelExporter.quantize_dynamic(model)
        q_params = sum(p.numel() for p in quantized.parameters())
        print(f"  量化后参数量: {q_params:,}")
    except Exception as e:
        print(f"  量化跳过: {e}")

    # ── Step 7: 生成 Dart 代码 ────────────────────────────────────────
    print("\n[Step 7] 生成 Dart 端代码片段 ...")
    dart_code = DartCodeGenerator.generate_dart_models()
    dart_path = os.path.join(os.path.dirname(__file__), "..", "dart", "lib", "generated_models.dart")
    dart_dir = os.path.dirname(dart_path)
    if os.path.exists(dart_dir):
        with open(dart_path, "w", encoding="utf-8") as f:
            f.write(dart_code)
        print(f"  Dart 模型代码已生成: {dart_path}")

    # ── 最终 JSON 输出 ────────────────────────────────────────────────
    print("\n" + "=" * 70)
    print("  完整 JSON 输出")
    print("=" * 70)
    print(json_str)

    # ── Flutter 前端使用示例 ──────────────────────────────────────────
    print("\n" + "=" * 70)
    print("  Flutter 前端使用示例 (伪代码)")
    print("=" * 70)
    flutter_example = """
    // Flutter 端使用示例
    // 1. 从后端 API 获取 JSON
    final jsonString = await http.get('/api/analysis/000001.SZ');

    // 2. 反序列化
    final payload = AnalysisPayload.fromJsonString(jsonString);

    // 3. 生成图表配置
    final generator = ChartConfigGenerator(
      payload: payload,
      closePrices: historicalCloses,
    );
    final overlay = generator.generatePredictionOverlay();
    final chartData = generator.buildCompleteChart(overlay: overlay);

    // 4. 渲染 fl_chart
    LineChart(chartData);
    """
    print(flutter_example)

    print("=" * 70)
    print("  闭环演示完成 ✓")
    print("=" * 70)


if __name__ == "__main__":
    main()
