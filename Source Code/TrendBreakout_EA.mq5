//+------------------------------------------------------------------+
//|                                             TrendBreakout_EA.mq5 |
//|   Proyek Sains Manajemen - EA trend-following multi-instrumen    |
//|                                                                  |
//|   Strategi : Donchian breakout + filter tren EMA + stop ATR      |
//|   Sifat    : 1 posisi per simbol, TANPA martingale / grid / HFT  |
//|   Leverage : eksposur nosional dibatasi InpMaxLeverage x ekuitas |
//+------------------------------------------------------------------+
#property copyright "Proyek Sains Manajemen"
#property version   "1.00"
#property description "Donchian breakout + EMA trend filter + ATR stop."
#property description "Tanpa martingale, grid, atau HFT. Satu posisi per simbol."

#include <Trade/Trade.mqh>

//--- Sinyal
input group "=== Sinyal ==="
input ENUM_TIMEFRAMES InpSignalTF      = PERIOD_H4; // Timeframe sinyal
input int             InpEntryPeriod   = 55;        // Periode breakout entry (bar)
input int             InpExitPeriod    = 20;        // Periode channel exit (bar)
input int             InpTrendMAPeriod = 200;       // Periode EMA filter tren (0 = mati)

//--- Risiko
input group "=== Manajemen Risiko ==="
input int             InpATRPeriod     = 20;        // Periode ATR
input double          InpATRStopMult   = 3.0;       // Stop loss awal = N x ATR
input double          InpATRTrailMult  = 4.0;       // Trailing stop = N x ATR (0 = mati)
input double          InpRiskPercent   = 1.0;       // Risiko per trade (% ekuitas)
input double          InpMaxLeverage   = 1.0;       // Batas eksposur nosional / ekuitas (1.0 = tanpa leverage)

//--- Lain-lain
input group "=== Lain-lain ==="
input bool            InpAllowLong     = true;      // Izinkan posisi beli
input bool            InpAllowShort    = true;      // Izinkan posisi jual
input int             InpMaxSpreadPts  = 0;         // Spread maksimum saat entry, point (0 = mati)
input ulong           InpMagic         = 20261010;  // Magic number

//--- Kriteria optimasi (OnTester)
input group "=== Kriteria Optimasi ==="
input double          InpMaxDDLimit    = 30.0;      // Batas drawdown ekuitas (%), di atas ini skor = 0
input int             InpMinTrades     = 30;        // Jumlah trade minimum agar skor dihitung

CTrade   g_trade;
int      g_hATR      = INVALID_HANDLE;
int      g_hMA       = INVALID_HANDLE;
datetime g_lastBar   = 0;
datetime g_testStart = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpEntryPeriod < 2 || InpExitPeriod < 2 || InpATRPeriod < 2)
     {
      Print("Parameter periode harus >= 2");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpATRStopMult <= 0 || InpRiskPercent <= 0)
     {
      Print("InpATRStopMult dan InpRiskPercent harus > 0");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_hATR = iATR(_Symbol, InpSignalTF, InpATRPeriod);
   if(g_hATR == INVALID_HANDLE)
     {
      Print("Gagal membuat handle ATR");
      return(INIT_FAILED);
     }
   if(InpTrendMAPeriod > 0)
     {
      g_hMA = iMA(_Symbol, InpSignalTF, InpTrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hMA == INVALID_HANDLE)
        {
         Print("Gagal membuat handle EMA");
         return(INIT_FAILED);
        }
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetDeviationInPoints(100);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hMA  != INVALID_HANDLE) IndicatorRelease(g_hMA);
  }

//+------------------------------------------------------------------+
//| Bulatkan harga ke tick size simbol                               |
//+------------------------------------------------------------------+
double NormalizePrice(const double price)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0) return(NormalizeDouble(price, _Digits));
   return(NormalizeDouble(MathRound(price / ts) * ts, _Digits));
  }

//+------------------------------------------------------------------+
//| Cari posisi milik EA ini di simbol ini (aman untuk akun hedging) |
//+------------------------------------------------------------------+
ulong FindMyPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return(ticket);
     }
   return(0);
  }

//+------------------------------------------------------------------+
//| Ukuran lot: berbasis risiko, dibatasi eksposur nosional & margin |
//+------------------------------------------------------------------+
double CalcLots(const ENUM_ORDER_TYPE type, const double price, const double slDist)
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ts     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tv     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(ts <= 0 || tv <= 0 || slDist <= 0 || price <= 0 || equity <= 0) return(0);

   // Nilai (mata uang akun) per 1.0 pergerakan harga untuk 1 lot
   double valuePerUnit = tv / ts;

   // 1) Lot berdasarkan risiko per trade
   double lots = (equity * InpRiskPercent / 100.0) / (slDist * valuePerUnit);

   // 2) Batas eksposur nosional (aturan "tanpa leverage")
   if(InpMaxLeverage > 0)
     {
      double notionalPerLot = price * valuePerUnit;
      double lotsCap        = (equity * InpMaxLeverage) / notionalPerLot;
      lots = MathMin(lots, lotsCap);
     }

   // 3) Pastikan margin cukup
   double margin = 0;
   if(OrderCalcMargin(type, _Symbol, lots, price, margin) && margin > 0)
     {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.95;
      if(margin > freeMargin) lots *= freeMargin / margin;
     }

   // 4) Sesuaikan dengan aturan volume simbol
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   if(lots < vmin)
     {
      // Tidak dipaksa ke lot minimum, supaya batas leverage tidak dilanggar
      Print("Lot terhitung di bawah minimum, entry dilewati. Naikkan deposit awal.");
      return(0);
     }
   if(lots > vmax) lots = vmax;
   return(NormalizeDouble(lots, 8));
  }

//+------------------------------------------------------------------+
//| Kelola posisi terbuka: exit channel + trailing ATR               |
//+------------------------------------------------------------------+
void ManagePosition(const ulong ticket, const double close1, const double atr)
  {
   if(!PositionSelectByTicket(ticket)) return;

   long   type  = PositionGetInteger(POSITION_TYPE);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   if(type == POSITION_TYPE_BUY)
     {
      int idx = iLowest(_Symbol, InpSignalTF, MODE_LOW, InpExitPeriod, 2);
      if(idx >= 0 && close1 < iLow(_Symbol, InpSignalTF, idx))
        {
         g_trade.PositionClose(ticket);
         return;
        }
      if(InpATRTrailMult > 0)
        {
         double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSL = NormalizePrice(close1 - InpATRTrailMult * atr);
         if(newSL > sl + point && newSL < bid - stops)
            g_trade.PositionModify(ticket, newSL, tp);
        }
     }
   else if(type == POSITION_TYPE_SELL)
     {
      int idx = iHighest(_Symbol, InpSignalTF, MODE_HIGH, InpExitPeriod, 2);
      if(idx >= 0 && close1 > iHigh(_Symbol, InpSignalTF, idx))
        {
         g_trade.PositionClose(ticket);
         return;
        }
      if(InpATRTrailMult > 0)
        {
         double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL = NormalizePrice(close1 + InpATRTrailMult * atr);
         if((sl == 0 || newSL < sl - point) && newSL > ask + stops)
            g_trade.PositionModify(ticket, newSL, tp);
        }
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(g_testStart == 0) g_testStart = TimeCurrent();

   // Hanya bekerja sekali per bar baru di timeframe sinyal (bukan HFT)
   datetime barTime = iTime(_Symbol, InpSignalTF, 0);
   if(barTime == 0 || barTime == g_lastBar) return;

   int need = MathMax(InpEntryPeriod, MathMax(InpExitPeriod, InpTrendMAPeriod)) + 5;
   if(Bars(_Symbol, InpSignalTF) < need) return;

   double atrBuf[1];
   if(CopyBuffer(g_hATR, 0, 1, 1, atrBuf) != 1) return;
   double atr = atrBuf[0];
   if(atr <= 0) return;

   double ma = 0;
   if(g_hMA != INVALID_HANDLE)
     {
      double maBuf[1];
      if(CopyBuffer(g_hMA, 0, 1, 1, maBuf) != 1) return;
      ma = maBuf[0];
     }

   double close1 = iClose(_Symbol, InpSignalTF, 1);
   if(close1 <= 0) return;

   g_lastBar = barTime; // data lengkap, bar ini dianggap sudah diproses

   //--- Ada posisi: kelola saja, tidak menambah posisi (bukan grid/martingale)
   ulong ticket = FindMyPosition();
   if(ticket > 0)
     {
      ManagePosition(ticket, close1, atr);
      return;
     }

   //--- Filter spread
   if(InpMaxSpreadPts > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts) return;

   //--- Channel Donchian dari bar 2 ke belakang (bar 1 adalah bar sinyal)
   int iHH = iHighest(_Symbol, InpSignalTF, MODE_HIGH, InpEntryPeriod, 2);
   int iLL = iLowest(_Symbol, InpSignalTF, MODE_LOW, InpEntryPeriod, 2);
   if(iHH < 0 || iLL < 0) return;
   double hh = iHigh(_Symbol, InpSignalTF, iHH);
   double ll = iLow(_Symbol, InpSignalTF, iLL);

   bool trendUp   = (g_hMA == INVALID_HANDLE) || (close1 > ma);
   bool trendDown = (g_hMA == INVALID_HANDLE) || (close1 < ma);

   double slDist = InpATRStopMult * atr;
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(slDist <= stops) return;

   if(InpAllowLong && trendUp && close1 > hh)
     {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lots = CalcLots(ORDER_TYPE_BUY, ask, slDist);
      if(lots > 0)
         g_trade.Buy(lots, _Symbol, 0.0, NormalizePrice(ask - slDist), 0.0, "TB long");
     }
   else if(InpAllowShort && trendDown && close1 < ll)
     {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double lots = CalcLots(ORDER_TYPE_SELL, bid, slDist);
      if(lots > 0)
         g_trade.Sell(lots, _Symbol, 0.0, NormalizePrice(bid + slDist), 0.0, "TB short");
     }
  }

//+------------------------------------------------------------------+
//| Kriteria optimasi kustom + laporan bulanan                       |
//|  Skor = CAGR(%) / MaxDD ekuitas(%)                               |
//|  Skor 0 jika DD > batas atau trade terlalu sedikit               |
//|  Skor dipotong 50% jika ada tahun dengan > 6 bulan rugi          |
//|  Di luar mode optimasi, hasil bulanan ditulis ke CSV di folder   |
//|  Common\Files (TB_monthly_<simbol>.csv)                          |
//+------------------------------------------------------------------+
double OnTester()
  {
   double deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double profit  = TesterStatistics(STAT_PROFIT);
   double ddPct   = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades  = TesterStatistics(STAT_TRADES);

   //--- Rekap bulanan dari riwayat deal
   int    mKey[];
   double mStart[];
   double mPnL[];
   int    months  = 0;
   double balance = 0;

   if(HistorySelect(0, TimeCurrent()))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         long   dtype  = HistoryDealGetInteger(deal, DEAL_TYPE);
         double amount = HistoryDealGetDouble(deal, DEAL_PROFIT)
                         + HistoryDealGetDouble(deal, DEAL_SWAP)
                         + HistoryDealGetDouble(deal, DEAL_COMMISSION)
                         + HistoryDealGetDouble(deal, DEAL_FEE);

         if(dtype == DEAL_TYPE_BALANCE)
           {
            balance += amount; // deposit awal
            continue;
           }
         if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL) continue;

         MqlDateTime dt;
         TimeToStruct((datetime)HistoryDealGetInteger(deal, DEAL_TIME), dt);
         int key = dt.year * 100 + dt.mon;

         if(months == 0 || mKey[months - 1] != key)
           {
            months++;
            ArrayResize(mKey, months);
            ArrayResize(mStart, months);
            ArrayResize(mPnL, months);
            mKey[months - 1]   = key;
            mStart[months - 1] = balance;
            mPnL[months - 1]   = 0;
           }
         mPnL[months - 1] += amount;
         balance          += amount;
        }
     }

   //--- Jumlah bulan rugi terbanyak dalam satu tahun
   int worstYearLosing = 0, curYear = 0, curLosing = 0;
   for(int m = 0; m < months; m++)
     {
      int y = mKey[m] / 100;
      if(y != curYear)
        {
         curYear   = y;
         curLosing = 0;
        }
      if(mPnL[m] < 0) curLosing++;
      if(curLosing > worstYearLosing) worstYearLosing = curLosing;
     }

   //--- Tulis CSV bulanan (hanya pada single test, bukan saat optimasi)
   if(!MQLInfoInteger(MQL_OPTIMIZATION))
     {
      string fname = "TB_monthly_" + _Symbol + ".csv";
      int fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(fh != INVALID_HANDLE)
        {
         FileWrite(fh, "Tahun", "Bulan", "SaldoAwal", "PnL", "ReturnPct");
         for(int m = 0; m < months; m++)
           {
            double ret = (mStart[m] > 0) ? 100.0 * mPnL[m] / mStart[m] : 0.0;
            FileWrite(fh, mKey[m] / 100, mKey[m] % 100,
                      DoubleToString(mStart[m], 2),
                      DoubleToString(mPnL[m], 2),
                      DoubleToString(ret, 2));
           }
         FileClose(fh);
         Print("Laporan bulanan ditulis ke Common\\Files\\", fname);
        }
      Print("Bulan rugi terbanyak dalam satu tahun: ", worstYearLosing);
     }

   //--- Skor
   if(deposit <= 0) return(0);
   double finalBal = deposit + profit;
   if(finalBal <= 0) return(-100.0);

   double years = (g_testStart > 0) ? (double)(TimeCurrent() - g_testStart) / (365.25 * 86400.0) : 0;
   if(years < 0.25) years = 0.25;
   double cagr = (MathPow(finalBal / deposit, 1.0 / years) - 1.0) * 100.0;

   if(!MQLInfoInteger(MQL_OPTIMIZATION))
      Print("CAGR: ", DoubleToString(cagr, 2), "% | Max DD ekuitas: ", DoubleToString(ddPct, 2), "%");

   if(cagr <= 0) return(cagr);
   if(trades < InpMinTrades || ddPct > InpMaxDDLimit) return(0);

   double score = cagr / MathMax(ddPct, 1.0);
   if(worstYearLosing > 6) score *= 0.5;
   return(score);
  }
//+------------------------------------------------------------------+
