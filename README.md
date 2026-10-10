# Industrial Grade Project: Multi-Asset Trend ATR Expert Advisor (Upgraded Version)

Upgrade of Project 2 for the Sains Manajemen course, Universitas Gadjah Mada.

**Author:** Devina Rahmadhita Dewantoro (24/532725/PA/22528)

This repository contains the MQL5 source code of the Expert Advisor and the MetaTrader 5 backtest and optimization results on two data sources: an Exness real account and the MetaQuotes-Demo account (History Quality 100%).

## Repository structure

| Folder | Contents |
| --- | --- |
| `Source Code` | `TrendBreakout_EA.mq5`, the Expert Advisor |
| `Exness Results` | Optimization results and final real-tick backtest reports for the 10 instruments tested on Exness |
| `MetaQuotes Result` | Optimization results and final real-tick backtest reports for the instruments tested on MetaQuotes-Demo |

File naming: `<symbol>_optimasi` is an optimization result, `<symbol>_final` is the final backtest report. Exness symbols end with `m` (for example `XAUUSDm`); MetaQuotes-Demo symbols do not.

## Strategy

`TrendBreakout_EA` is a trend-following EA. Compared with Project 2, the entry logic (EMA crossover with ADX and RSI filters on H1) was replaced with a price breakout on D1. ATR is still used for stops.

- **Entry:** the last daily close breaks the highest high (buy) or lowest low (sell) of the previous N bars, in the direction of the EMA trend filter.
- **Initial stop loss:** a multiple of ATR(20).
- **Exit:** close beyond the opposite M-bar channel, or an ATR trailing stop that only moves in the direction of profit.
- **Position size:** the smaller of 3% equity risk per trade and a notional exposure cap of 1x equity.
- **Direction:** long only for metals, indices, and crypto; long and short for forex and energy.

Assignment constraints are enforced in the code:

- **No martingale or grid:** one position per symbol, never adds to an open position.
- **No HFT:** logic runs once per new daily bar.
- **No leverage:** position value is capped at 1x equity; if the minimum lot exceeds the cap, the entry is skipped.

## Test setup

| Setting | Value |
| --- | --- |
| Platform | MetaTrader 5 Strategy Tester |
| Period | 1 October 2019 to 1 October 2026 (7 years) |
| Deposit and leverage | USD 100,000, 1:1 |
| Final test model | Every tick based on real ticks |
| Optimization | Fast genetic based algorithm, 1 minute OHLC, criterion Custom max |
| Signal timeframe | D1 |

The Custom max criterion is defined in `OnTester()`: annual growth divided by maximum equity drawdown. The score is zero if drawdown exceeds 30% or there are fewer than 10 trades, and is halved if any year has more than six losing months.

Optimized parameters: breakout entry period, channel exit period, EMA trend period, ATR stop multiplier, ATR trailing multiplier.

## Results on Exness (real account, 10 instruments)

| Instrument | Class | 7-year profit | Per year | Max equity DD | Profit factor | Trades | History Quality |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ETHUSDm | Crypto | 269.6% | 20.5% | 23.33% | 2.80 | 32 | 10% |
| BTCUSDm | Crypto | 129.7% | 12.6% | 19.35% | 3.36 | 28 | 39% |
| XAUUSDm | Metal | 64.4% | 7.4% | 11.64% | 3.78 | 24 | 3% |
| JP225m | Index | 49.6% | 5.9% | 16.17% | 2.59 | 28 | 10% |
| XAGUSDm | Metal | 34.4% | 4.3% | 15.70% | 1.72 | 53 | 10% |
| USDJPYm | Forex | 23.4% | 3.0% | 12.18% | 1.74 | 48 | 10% |
| USTECm | Index | 22.5% | 2.9% | 12.89% | 1.78 | 24 | 10% |
| USOILm | Energy | 20.4% | 2.7% | 12.21% | 1.81 | 51 | 10% |
| EURUSDm | Forex | 7.6% | 1.1% | 9.23% | 1.23 | 69 | 39% |
| UKOILm | Energy | 3.5% | 0.5% | 14.44% | 1.31 | 20 | 10% |

## Results on MetaQuotes-Demo (History Quality 100%)

| Instrument | Parameters (entry / exit / EMA / stop / trail) | 7-year profit | Per year | Max equity DD | Profit factor | Trades |
| --- | --- | --- | --- | --- | --- | --- |
| XAUUSD | 30 / 40 / 50 / 3.0 / 3.0 | 89.5% | 9.6% | 11.74% | 5.46 | 23 |
| USDJPY | 10 / 45 / 200 / 4.0 / 5.0 | 22.5% | 2.9% | 9.0% | 2.76 | 26 |
| EURUSD | 10 / 5 / 100 / 2.0 / 3.0 | 11.7% | 1.6% | 7.09% | 1.36 | 74 |
| XAGUSD | 10 / 5 / 200 / 3.0 / 3.0 | 91.6% | 9.7% | 34.18% | 1.81 | 42 |

XAGUSD exceeds the 30% drawdown limit on this data source. Crypto, energy, and index instruments could not be tested on MetaQuotes-Demo: crypto and energy symbols are not offered, and index symbols could not be opened without leverage.

## Evaluation against the assignment

| Requirement | Status |
| --- | --- |
| 10 instruments across forex, metals, indices, crypto, energy | Met |
| No martingale, grid, or HFT | Met |
| No leverage | Met (exposure capped at 1x equity, tester leverage 1:1) |
| Maximum drawdown 25 to 30% | Met on all 10 Exness instruments |
| No more than six losing months per year | Met on 9 of 10 Exness instruments (not EURUSDm) |
| 7 years, every tick based on real ticks | Used for all final tests; Exness History Quality is only 3 to 39% |
| Monthly target 3 to 5%, annual target 50 to 70% | Not achieved (0.5% to 20.5% per year) |

## Limitations

- With exposure capped at 1x equity, returns cannot greatly exceed the trend of the instrument itself, so the annual return target was not reached.
- Exness provides real ticks for only a small part of the 7-year period.
- Each instrument produced only 20 to 74 trades in 7 years, so results are sensitive to a few large trades.
- Parameters were selected on the same period used for testing, without a forward test. The Exness parameters for USDJPY lost 3.1% on MetaQuotes data before re-optimization.
- Instruments were tested separately; combined portfolio drawdown was not measured.

## How to reproduce

1. Copy `TrendBreakout_EA.mq5` to `MQL5/Experts` and compile it in MetaEditor.
2. Open the Strategy Tester and apply the settings in the Test setup table.
3. Enter the parameters for the instrument and run a single test with Optimization disabled.

Each single test also writes a monthly profit summary to `TB_monthly_<symbol>.csv` in the MetaTrader `Common\Files` folder.
