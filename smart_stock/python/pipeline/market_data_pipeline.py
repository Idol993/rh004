"""
market_data_pipeline.py
=======================
多因子特征工程管道 —— 将原始 OHLCV 数据转化为模型可读张量。

核心类 MarketDataPipeline 实现了：
  1. 基础技术指标计算（MACD / RSI / Bollinger Bands）
  2. 微观结构因子（量价相关性、订单流不平衡代理）
  3. 动量因子标准化
  4. 自适应滚动 Z-Score 归一化（防止未来函数泄露）
  5. 缺失值 / 异常值处理（EWMA 填充 + IQR 截断）
  6. 时间滑窗切片 → PyTorch Tensor [Batch, Time_Steps, Features]
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import torch
from typing import Generator, Tuple

try:
    import talib
    HAS_TALIB = True
except ImportError:
    HAS_TALIB = False


def _ema(series: pd.Series, span: int) -> pd.Series:
    return series.ewm(span=span, adjust=False).mean()


def _sma(series: pd.Series, window: int) -> pd.Series:
    return series.rolling(window=window, min_periods=1).mean()


def _std_rolling(series: pd.Series, window: int) -> pd.Series:
    return series.rolling(window=window, min_periods=1).std()


class MarketDataPipeline:
    """将 OHLCV DataFrame 转化为 [Batch, Time_Steps, Features] 张量的管道。

    Parameters
    ----------
    window_size : int
        滑窗长度（时间步数）。
    zscore_window : int
        滚动 Z-Score 归一化窗口，默认 60。
    ewma_span : int
        缺失值 EWMA 填充的跨度，默认 20。
    iqr_multiplier : float
        IQR 异常值截断倍数，默认 1.5。
    step : int
        滑窗步长，默认 1。
    """

    def __init__(
        self,
        window_size: int = 60,
        zscore_window: int = 60,
        ewma_span: int = 20,
        iqr_multiplier: float = 1.5,
        step: int = 1,
    ) -> None:
        self.window_size = window_size
        self.zscore_window = zscore_window
        self.ewma_span = ewma_span
        self.iqr_multiplier = iqr_multiplier
        self.step = step
        self._feature_names: list[str] = []

    # ------------------------------------------------------------------
    # 公开接口
    # ------------------------------------------------------------------

    @property
    def feature_names(self) -> list[str]:
        return list(self._feature_names)

    def fit_transform(self, df: pd.DataFrame) -> torch.Tensor:
        """一站式处理：计算因子 → 归一化 → 填充 → 返回完整张量。

        Parameters
        ----------
        df : pd.DataFrame
            必须包含 open / high / low / close / volume 列。

        Returns
        -------
        torch.Tensor
            形状 [N, Time_Steps, Features]。
        """
        df = self._validate_input(df)
        df = self._compute_technical_indicators(df)
        df = self._compute_microstructure_factors(df)
        df = self._compute_momentum_factors(df)
        df = self._handle_missing_and_outliers(df)
        df = self._adaptive_zscore_normalize(df)
        df = df.dropna()
        self._feature_names = [c for c in df.columns if c not in ("open", "high", "low", "close", "volume")]
        feature_df = df[self._feature_names]
        return self._sliding_window_to_tensor(feature_df.values)

    def stream_slices(
        self, df: pd.DataFrame
    ) -> Generator[Tuple[torch.Tensor, int], None, None]:
        """生成器模式：逐批产出 (tensor_slice, end_index)。"""
        df = self._validate_input(df)
        df = self._compute_technical_indicators(df)
        df = self._compute_microstructure_factors(df)
        df = self._compute_momentum_factors(df)
        df = self._handle_missing_and_outliers(df)
        df = self._adaptive_zscore_normalize(df)
        df = df.dropna()
        self._feature_names = [c for c in df.columns if c not in ("open", "high", "low", "close", "volume")]
        feature_df = df[self._feature_names]
        arr = feature_df.values.astype(np.float32)
        n = len(arr)
        for start in range(0, n - self.window_size + 1, self.step):
            window = arr[start : start + self.window_size]
            yield torch.from_numpy(window[np.newaxis, :, :]), start + self.window_size - 1

    # ------------------------------------------------------------------
    # 因子计算
    # ------------------------------------------------------------------

    def _compute_technical_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        """计算 MACD / RSI / Bollinger Bands。"""
        close = df["close"].astype(np.float64)
        high = df["high"].astype(np.float64)
        low = df["low"].astype(np.float64)

        if HAS_TALIB:
            macd, macd_signal, macd_hist = talib.MACD(close)
            df["macd"] = macd
            df["macd_signal"] = macd_signal
            df["macd_hist"] = macd_hist
            df["rsi_14"] = talib.RSI(close, timeperiod=14)
            upper, mid, lower = talib.BBANDS(
                close, timeperiod=20, nbdevup=2, nbdevdn=2
            )
            df["bb_upper"] = upper
            df["bb_mid"] = mid
            df["bb_lower"] = lower
        else:
            ema12 = _ema(close, 12)
            ema26 = _ema(close, 26)
            df["macd"] = ema12 - ema26
            df["macd_signal"] = _ema(df["macd"], 9)
            df["macd_hist"] = df["macd"] - df["macd_signal"]
            df["rsi_14"] = self._compute_rsi(close, 14)
            bb_mid = _sma(close, 20)
            bb_std = _std_rolling(close, 20)
            df["bb_upper"] = bb_mid + 2 * bb_std
            df["bb_mid"] = bb_mid
            df["bb_lower"] = bb_mid - 2 * bb_std

        df["bb_pct"] = (close - df["bb_lower"]) / (df["bb_upper"] - df["bb_lower"] + 1e-8)
        df["atr_14"] = self._compute_atr(high, low, close, 14)
        return df

    @staticmethod
    def _compute_rsi(close: pd.Series, period: int = 14) -> pd.Series:
        """RSI 计算。

        RSI = 100 - 100 / (1 + RS)
        RS = EMA(gain, period) / EMA(loss, period)
        """
        delta = close.diff()
        gain = delta.clip(lower=0)
        loss = (-delta).clip(lower=0)
        avg_gain = gain.ewm(span=period, adjust=False).mean()
        avg_loss = loss.ewm(span=period, adjust=False).mean()
        rs = avg_gain / (avg_loss + 1e-10)
        return 100.0 - 100.0 / (1.0 + rs)

    @staticmethod
    def _compute_atr(
        high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14
    ) -> pd.Series:
        """Average True Range。

        TR = max(H - L, |H - C_prev|, |L - C_prev|)
        ATR = EMA(TR, period)
        """
        prev_close = close.shift(1)
        tr1 = high - low
        tr2 = (high - prev_close).abs()
        tr3 = (low - prev_close).abs()
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        return tr.ewm(span=period, adjust=False).mean()

    # ------------------------------------------------------------------
    # 微观结构因子
    # ------------------------------------------------------------------

    def _compute_microstructure_factors(self, df: pd.DataFrame) -> pd.DataFrame:
        """微观结构因子：量价相关性、成交量变化率、VWAP 偏差。

        - volume_price_corr: 滚动窗口内收益率与成交量的 Pearson 相关系数，
          衡量量价协同程度（微观结构核心指标）。
        - volume_change: 成交量环比变化率。
        - vwap_deviation: 成交价相对 VWAP 的偏离度。
        """
        close = df["close"].astype(np.float64)
        volume = df["volume"].astype(np.float64)
        high = df["high"].astype(np.float64)
        low = df["low"].astype(np.float64)

        returns = close.pct_change()

        corr_window = 20
        df["volume_price_corr"] = (
            returns.rolling(corr_window, min_periods=5)
            .corr(volume)
        )

        df["volume_change"] = volume.pct_change()

        typical_price = (high + low + close) / 3.0
        vwap = (typical_price * volume).cumsum() / volume.cumsum()
        df["vwap_deviation"] = (close - vwap) / (vwap + 1e-8)

        df["obv"] = self._compute_obv(close, volume)
        df["obv_change"] = df["obv"].pct_change()

        return df

    @staticmethod
    def _compute_obv(close: pd.Series, volume: pd.Series) -> pd.Series:
        """On-Balance Volume。

        OBV_t = OBV_{t-1} + volume_t   if close_t > close_{t-1}
              = OBV_{t-1} - volume_t   if close_t < close_{t-1}
              = OBV_{t-1}              otherwise
        """
        direction = np.sign(close.diff())
        direction.iloc[0] = 0
        return (direction * volume).cumsum()

    # ------------------------------------------------------------------
    # 动量因子
    # ------------------------------------------------------------------

    def _compute_momentum_factors(self, df: pd.DataFrame) -> pd.DataFrame:
        """动量因子：多周期收益率、加速度。

        - roc_n: n 日变动率 Rate of Change = (C_t - C_{t-n}) / C_{t-n}
        - momentum_accel: 动量加速度 = ROC_5 - ROC_5 滞后一阶差分
        - ts_rank_20: 20 日时序排名百分位
        """
        close = df["close"].astype(np.float64)

        for period in [5, 10, 20]:
            df[f"roc_{period}"] = close.pct_change(period)

        df["momentum_accel"] = df["roc_5"].diff()

        df["ts_rank_20"] = (
            close.rolling(20, min_periods=5)
            .rank(pct=True)
        )

        return df

    # ------------------------------------------------------------------
    # 数据预处理
    # ------------------------------------------------------------------

    def _handle_missing_and_outliers(self, df: pd.DataFrame) -> pd.DataFrame:
        """缺失值与异常值处理。

        1. 用 EWMA 填充 NaN（指数加权移动平均能保留局部趋势）。
        2. IQR 方法截断异常值。
        """
        numeric_cols = df.select_dtypes(include=[np.number]).columns
        for col in numeric_cols:
            ewma = _ema(df[col].interpolate(), self.ewma_span)
            df[col] = df[col].fillna(ewma)

        for col in numeric_cols:
            q1 = df[col].quantile(0.25)
            q3 = df[col].quantile(0.75)
            iqr = q3 - q1
            lower = q1 - self.iqr_multiplier * iqr
            upper = q3 + self.iqr_multiplier * iqr
            df[col] = df[col].clip(lower=lower, upper=upper)

        return df

    def _adaptive_zscore_normalize(self, df: pd.DataFrame) -> pd.DataFrame:
        """自适应滚动 Z-Score 归一化，防止未来函数泄露。

        对每个时间点 t，仅使用 [t - zscore_window + 1, t] 范围内的数据
        计算 mean 和 std，确保不引入未来信息：

            z_t = (x_t - μ_{t-w:t}) / (σ_{t-w:t} + ε)
        """
        numeric_cols = df.select_dtypes(include=[np.number]).columns
        skip = {"open", "high", "low", "close", "volume"}
        norm_cols = [c for c in numeric_cols if c not in skip]

        for col in norm_cols:
            rolling_mean = df[col].rolling(self.zscore_window, min_periods=5).mean()
            rolling_std = df[col].rolling(self.zscore_window, min_periods=5).std()
            df[col] = (df[col] - rolling_mean) / (rolling_std + 1e-8)

        return df

    # ------------------------------------------------------------------
    # 序列切片
    # ------------------------------------------------------------------

    def _sliding_window_to_tensor(self, arr: np.ndarray) -> torch.Tensor:
        """基于时间滑窗切分序列，输出 [Batch, Time_Steps, Features]。

        Sliding Window 切片：
            slice_i = arr[i : i + window_size, :]
        步长为 self.step，共生成 N = (L - window_size) // step + 1 个切片。
        """
        n = len(arr)
        if n < self.window_size:
            raise ValueError(
                f"数据长度 {n} 小于窗口大小 {self.window_size}"
            )
        windows = []
        for start in range(0, n - self.window_size + 1, self.step):
            windows.append(arr[start : start + self.window_size])
        return torch.from_numpy(np.stack(windows).astype(np.float32))

    # ------------------------------------------------------------------
    # 辅助
    # ------------------------------------------------------------------

    @staticmethod
    def _validate_input(df: pd.DataFrame) -> pd.DataFrame:
        required = {"open", "high", "low", "close", "volume"}
        missing = required - set(df.columns.str.lower())
        if missing:
            raise KeyError(f"输入 DataFrame 缺少列: {missing}")
        df.columns = [c.lower() for c in df.columns]
        return df.copy()
