//+------------------------------------------------------------------+
//|                                              ReplayPanel.mq5     |
//|  EA de controle do replay NAS100_SIM                             |
//|                                                                  |
//|  REQUISITO: adicione ApiUrl em                                   |
//|  Ferramentas > Opções > Expert Advisors > Permitir WebRequest    |
//+------------------------------------------------------------------+
#property copyright "Trading CRM"
#property version   "1.00"
#property description "Painel visual de controle do replay NAS100"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string   ApiUrl        = "https://trading-crm-main.vercel.app/api/trades";
input string   ApiKey        = "nas100-sim-2026";
input double   StartCapital  = 600.0;
input double   RiskPercent   = 14.0;
input double   DefaultSLprice = 4.00;  // distância do SL em preço (ex: 4.00 = 400pts NAS100)
input double   DefaultTPprice = 8.00;  // distância do TP em preço
input string   DestSymbol    = "NAS100_SIM";
input string   SourceSymbol  = "NAS100";

//+------------------------------------------------------------------+
//| Constantes                                                       |
//+------------------------------------------------------------------+
#define PRE          "RP_"
#define CMD_FILE     "replay_cmd.txt"
#define FALLBACK_CSV "fallback_trades.csv"

// Cores do painel
#define CLR_BG       C'28,28,32'
#define CLR_BG2      C'38,38,44'
#define CLR_TEXT     clrWhite
#define CLR_MUTED    C'140,140,155'
#define CLR_BUY      C'34,100,220'
#define CLR_SELL     C'200,48,48'
#define CLR_CLOSE    C'70,70,80'
#define CLR_SPD_ON   C'60,120,60'
#define CLR_SPD_OFF  C'55,55,65'
#define CLR_PAUSE    C'130,100,20'
#define CLR_WIN      C'22,100,55'
#define CLR_LOSS     C'130,30,30'

// Geometria do painel (fixo, canto superior-esquerdo)
#define PX  10
#define PY  30
#define PW  236
#define PH  360

//+------------------------------------------------------------------+
//| Struct de posição virtual                                        |
//+------------------------------------------------------------------+
struct VirtualPosition
{
   bool     isOpen;
   string   direction;   // "LONG" ou "SHORT"
   datetime entryTime;
   double   entryPrice;
   double   slPrice;
   double   tpPrice;
   double   slDist;
   double   tpDist;
   double   lotSize;
   double   riskUsd;
   double   capitalAtEntry;
   double   mfePts;      // max favorable excursion em pontos
   double   maePts;      // max adverse excursion em pontos
   bool     hit[6];      // hit[1]=1R .. hit[5]=5R (índice 0 não usado)
};

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
double          g_capital;
double          g_slDist;
double          g_tpDist;
int             g_speed;
bool            g_paused;
VirtualPosition g_pos;
datetime        g_flashEnd;
bool            g_flashWin;

// Dados do símbolo (populados em RefreshSymbolInfo)
double          g_tickVal;
double          g_tickSz;
double          g_contractSz;
double          g_point;

// Risco ajustável em tempo real (inicializado a partir do input RiskPercent)
double          g_riskPct;

int             g_timerCount = 0;
bool            g_navigated  = false;

// Nomes das linhas horizontais
const string SL_LINE = PRE "SL";
const string TP_LINE = PRE "TP";
const string EN_LINE = PRE "Entry";

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_capital    = StartCapital;
   g_riskPct    = RiskPercent;
   g_slDist     = DefaultSLprice;
   g_tpDist     = DefaultTPprice;
   g_speed      = 1;
   g_paused     = false;
   g_flashEnd   = 0;

   ZeroMemory(g_pos);
   g_pos.isOpen = false;

   RefreshSymbolInfo();

   FolderCreate("screenshots");

   PanelCreate();
   PanelUpdate();

   EventSetTimer(1);
   ChartRedraw();

   // Abre M5 e H1 apenas se ainda não estiverem abertos
   bool m5Open = false, h1Open = false;
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(ChartSymbol(chartId) == DestSymbol)
      {
         if(ChartPeriod(chartId) == PERIOD_M5) m5Open = true;
         if(ChartPeriod(chartId) == PERIOD_H1) h1Open = true;
      }
      chartId = ChartNext(chartId);
   }

   if(!m5Open)
   {
      long chartM5 = ChartOpen(DestSymbol, PERIOD_M5);
      if(chartM5 > 0) ChartSetInteger(chartM5, CHART_SHOW_GRID, false);
   }
   if(!h1Open)
   {
      long chartH1 = ChartOpen(DestSymbol, PERIOD_H1);
      if(chartH1 > 0) ChartSetInteger(chartH1, CHART_SHOW_GRID, false);
   }

   Print("[ReplayPanel] Gráficos M5 e H1 verificados/abertos");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   PanelDelete();
   ObjectDelete(0, SL_LINE);
   ObjectDelete(0, TP_LINE);
   ObjectDelete(0, EN_LINE);
   RemoveLinesFromOtherCharts();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   RefreshSymbolInfo();

   MqlTick t;
   if(!SymbolInfoTick(DestSymbol, t)) return;

   if(g_pos.isOpen)
   {
      UpdateMaeMfe(t);
      MonitorPosition(t);
   }

   PanelUpdate();
}

//+------------------------------------------------------------------+
//| OnTimer — controla flash visual                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Navegação inicial — executa uma vez após o primeiro timer
   if(!g_navigated)
   {
      g_navigated = true;
      long chartId = ChartFirst();
      while(chartId >= 0)
      {
         if(ChartSymbol(chartId) == DestSymbol)
         {
            ChartSetInteger(chartId, CHART_AUTOSCROLL, true);
            ChartNavigate(chartId, CHART_END, 0);
            ChartRedraw(chartId);
         }
         chartId = ChartNext(chartId);
      }
      return;
   }

   g_timerCount++;

   if(g_flashEnd != 0 && TimeCurrent() >= g_flashEnd)
   {
      g_flashEnd = 0;
      ObjectSetInteger(0, PRE "BG", OBJPROP_BGCOLOR, CLR_BG);
      ChartRedraw();
   }

   if(g_timerCount % 2 == 0)
      SyncManualObjects();
}

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
      HandleButtonClick(sparam);

   else if(id == CHARTEVENT_OBJECT_DRAG && sparam == SL_LINE)
      HandleSLDrag();

   else if(id == CHARTEVENT_OBJECT_DRAG && sparam == TP_LINE)
      HandleTPDrag();

   else if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(ChartPeriod(0) != PERIOD_M15)
      {
         ChartSetSymbolPeriod(0, DestSymbol, PERIOD_M15);
         Print("[ReplayPanel] Timeframe travado em M15 — use janelas separadas para M5 e H1");
      }
      PanelDelete();
      PanelCreate();
      PanelUpdate();
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| RefreshSymbolInfo                                                |
//+------------------------------------------------------------------+
void RefreshSymbolInfo()
{
   g_tickVal    = SymbolInfoDouble(DestSymbol, SYMBOL_TRADE_TICK_VALUE);
   g_tickSz     = SymbolInfoDouble(DestSymbol, SYMBOL_TRADE_TICK_SIZE);
   g_contractSz = SymbolInfoDouble(DestSymbol, SYMBOL_TRADE_CONTRACT_SIZE);
   g_point      = SymbolInfoDouble(DestSymbol, SYMBOL_POINT);
   if(g_tickSz   <= 0) g_tickSz   = 0.01;
   if(g_tickVal  <= 0) g_tickVal  = 1.0;
   if(g_contractSz <= 0) g_contractSz = 1.0;
   if(g_point    <= 0) g_point    = 0.01;
}

//+------------------------------------------------------------------+
//| CalcRiskUsd                                                      |
//+------------------------------------------------------------------+
double CalcRiskUsd()
{
   return g_capital * g_riskPct / 100.0;
}

//+------------------------------------------------------------------+
//| CalcLot — riskUsd / (slDist * lotValue)                          |
//+------------------------------------------------------------------+
double CalcLot(double slDist)
{
   double riskUsd  = g_capital * g_riskPct / 100.0;
   double lotValue = g_contractSz * g_tickVal / g_tickSz;
   if(lotValue <= 0) lotValue = 100.0;
   double lot = riskUsd / (slDist * lotValue);
   return NormalizeDouble(MathMax(lot, 0.01), 2);
}

//+------------------------------------------------------------------+
//| CalcPnl — pnl flutuante em USD                                   |
//+------------------------------------------------------------------+
double CalcPnl(double exitPrice)
{
   if(!g_pos.isOpen) return 0;
   double diff = (g_pos.direction == "LONG")
                 ? exitPrice - g_pos.entryPrice
                 : g_pos.entryPrice - exitPrice;
   return diff * g_pos.lotSize * g_contractSz / g_tickSz * g_tickVal;
}

//+------------------------------------------------------------------+
//| UpdateMaeMfe — atualiza em tempo real durante a posição          |
//+------------------------------------------------------------------+
void UpdateMaeMfe(const MqlTick &t)
{
   double fav, adv;
   if(g_pos.direction == "LONG")
   {
      fav = t.bid - g_pos.entryPrice;
      adv = g_pos.entryPrice - t.bid;
   }
   else
   {
      fav = g_pos.entryPrice - t.ask;
      adv = t.ask - g_pos.entryPrice;
   }
   double favPts = fav / g_point;
   double advPts = adv / g_point;
   if(favPts > g_pos.mfePts) g_pos.mfePts = favPts;
   if(advPts > g_pos.maePts) g_pos.maePts = advPts;

   // hit1R–hit5R
   double slPts = g_pos.slDist / g_point;
   for(int r=1; r<=5; r++)
      if(!g_pos.hit[r] && g_pos.mfePts >= r * slPts)
         g_pos.hit[r] = true;
}

//+------------------------------------------------------------------+
//| MonitorPosition — verifica SL/TP a cada tick                     |
//+------------------------------------------------------------------+
void MonitorPosition(const MqlTick &t)
{
   double check = (g_pos.direction == "LONG") ? t.bid : t.ask;

   bool hitSL = (g_pos.direction == "LONG") ? check <= g_pos.slPrice : check >= g_pos.slPrice;
   bool hitTP = (g_pos.direction == "LONG") ? check >= g_pos.tpPrice : check <= g_pos.tpPrice;

   if(hitTP)       { ClosePosition((g_pos.direction=="LONG")?t.bid:t.ask, "TP", t);   return; }
   if(hitSL)       { ClosePosition((g_pos.direction=="LONG")?t.bid:t.ask, "SL", t);   return; }
}

//+------------------------------------------------------------------+
//| OpenPosition                                                     |
//+------------------------------------------------------------------+
void OpenPosition(string direction)
{
   MqlTick t;
   if(!SymbolInfoTick(DestSymbol, t)) { Print("[ReplayPanel] Sem tick de ", DestSymbol); return; }

   RefreshSymbolInfo();

   g_pos.isOpen        = true;
   g_pos.direction     = direction;
   g_pos.entryTime     = t.time;
   g_pos.entryPrice    = (direction == "LONG") ? t.ask : t.bid;
   g_pos.slDist        = g_slDist;
   g_pos.tpDist        = g_tpDist;
   g_pos.lotSize       = CalcLot(g_slDist);
   g_pos.riskUsd       = CalcRiskUsd();
   g_pos.capitalAtEntry= g_capital;
   g_pos.mfePts        = 0;
   g_pos.maePts        = 0;
   ArrayInitialize(g_pos.hit, false);

   double entry  = g_pos.entryPrice;
   double slDist = g_slDist;
   double tpDist = g_tpDist;

   g_pos.slPrice = (direction == "LONG") ? entry - slDist : entry + slDist;
   g_pos.tpPrice = (direction == "LONG") ? entry + tpDist : entry - tpDist;

   DrawLines(entry, g_pos.slPrice, g_pos.tpPrice);
   SyncLinesToOtherCharts();
   TakeScreenshot("open_" + direction + "_" + IntegerToString((int)t.time));
   PanelUpdate();
   ChartRedraw();

   PrintFormat("[ReplayPanel] %s aberto @ %.2f | SL %.2f | TP %.2f | Lote %.2f | Risco $%.2f",
               direction, entry, g_pos.slPrice, g_pos.tpPrice, g_pos.lotSize, g_pos.riskUsd);
}

//+------------------------------------------------------------------+
//| ClosePosition                                                    |
//+------------------------------------------------------------------+
void ClosePosition(double exitPrice, string reason, const MqlTick &t)
{
   if(!g_pos.isOpen) return;

   datetime exitTime    = t.time;
   double   pnl         = CalcPnl(exitPrice);
   double   resultR     = (g_pos.riskUsd > 0) ? pnl / g_pos.riskUsd : 0;
   int      durationMin = (int)((exitTime - g_pos.entryTime) / 60);

   g_capital += pnl;
   bool win = pnl >= 0;

   TakeScreenshot("close_" + reason + "_" + IntegerToString((int)exitTime));

   ComputePostExitMaeMfe(exitTime);
   string json = BuildJson(exitPrice, reason, exitTime, durationMin, pnl, resultR);
   SendTradeToApi(json);

   FlashPanel(win);
   ObjectDelete(0, SL_LINE);
   ObjectDelete(0, TP_LINE);
   ObjectDelete(0, EN_LINE);
   RemoveLinesFromOtherCharts();

   g_pos.isOpen = false;
   PanelUpdate();
   ChartRedraw();

   PrintFormat("[ReplayPanel] %s fechado %s @ %.2f | PnL $%.2f (%.2fR) | Capital $%.2f",
               g_pos.direction, reason, exitPrice, pnl, resultR, g_capital);
}

//+------------------------------------------------------------------+
//| HandleSLDrag — SL line foi arrastada pelo usuário                |
//+------------------------------------------------------------------+
void HandleSLDrag()
{
   double newSL = ObjectGetDouble(0, SL_LINE, OBJPROP_PRICE);
   if(newSL <= 0) return;

   g_pos.slPrice = newSL;
   g_pos.slDist  = MathAbs(newSL - g_pos.entryPrice);
   g_slDist      = g_pos.slDist;

   SyncLinesToOtherCharts();
   PanelUpdate();
}

//+------------------------------------------------------------------+
//| HandleTPDrag — TP line foi arrastada pelo usuário                |
//+------------------------------------------------------------------+
void HandleTPDrag()
{
   double newTP = ObjectGetDouble(0, TP_LINE, OBJPROP_PRICE);
   if(newTP <= 0) return;

   g_pos.tpPrice = newTP;
   g_pos.tpDist  = MathAbs(newTP - g_pos.entryPrice);
   g_tpDist      = g_pos.tpDist;

   SyncLinesToOtherCharts();
   PanelUpdate();
}

//+------------------------------------------------------------------+
//| HandleButtonClick                                                |
//+------------------------------------------------------------------+
void HandleButtonClick(const string name)
{
   // reset estado do botão (evita ficar pressionado visualmente)
   ObjectSetInteger(0, name, OBJPROP_STATE, false);

   if(name == PRE "RISK_UP") { g_riskPct = MathMin(g_riskPct + 1.0, 50.0); PanelUpdate(); return; }
   if(name == PRE "RISK_DN") { g_riskPct = MathMax(g_riskPct - 1.0,  1.0); PanelUpdate(); return; }

   if(name == PRE "BUY")       { if(!g_pos.isOpen) OpenPosition("LONG");  return; }
   if(name == PRE "SELL")      { if(!g_pos.isOpen) OpenPosition("SHORT"); return; }
   if(name == PRE "CLOSE")
   {
      if(g_pos.isOpen)
      {
         MqlTick t;
         if(SymbolInfoTick(DestSymbol, t))
         {
            double ep = (g_pos.direction=="LONG") ? t.bid : t.ask;
            ClosePosition(ep, "MANUAL", t);
         }
      }
      return;
   }

   if(name == PRE "PAUSE")
   {
      g_paused = !g_paused;
      WriteCmd(g_paused ? "PAUSE" : "PLAY");
      PanelUpdate();
      return;
   }

   // Botões de velocidade
   string speedNames[] = { PRE "SPD1", PRE "SPD2", PRE "SPD4", PRE "SPD8" };
   int    speedVals[]  = { 1, 2, 4, 8 };
   for(int i=0; i<4; i++)
   {
      if(name == speedNames[i])
      {
         g_speed = speedVals[i];
         WriteCmd("SPEED:" + IntegerToString(g_speed));
         PanelUpdate();
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| WriteCmd — escreve comando em replay_cmd.txt                     |
//+------------------------------------------------------------------+
void WriteCmd(const string cmd)
{
   int h = FileOpen(CMD_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { Print("[ReplayPanel] Falha ao escrever cmd: ", GetLastError()); return; }
   FileWriteString(h, cmd);
   FileClose(h);
}

//+------------------------------------------------------------------+
//| IsoTime — converte datetime para ISO 8601 UTC                    |
//+------------------------------------------------------------------+
string IsoTime(datetime dt)
{
   MqlDateTime s;
   TimeToStruct(dt, s);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02d.000Z",
                       s.year, s.mon, s.day, s.hour, s.min, s.sec);
}

//+------------------------------------------------------------------+
//| BoolStr                                                          |
//+------------------------------------------------------------------+
string BoolStr(bool v) { return v ? "true" : "false"; }

//+------------------------------------------------------------------+
//| BuildJson                                                        |
//+------------------------------------------------------------------+
string BuildJson(double exitPrice, string reason, datetime exitTime,
                 int durationMin, double pnlNet, double resultR)
{
   // sessionDate = só a data (zerando hora)
   MqlDateTime ed;
   TimeToStruct(g_pos.entryTime, ed);
   ed.hour = 0; ed.min = 0; ed.sec = 0;
   datetime sessDate = StructToTime(ed);

   string dir = (g_pos.direction == "LONG") ? "LONG" : "SHORT";

   string j = "{"
      "\"instrument\":\"NAS100\","
      "\"direction\":\"" + dir + "\","
      "\"source\":\"SIMULATOR\","
      "\"exitReason\":\"" + reason + "\","
      "\"entryTime\":\"" + IsoTime(g_pos.entryTime) + "\","
      "\"sessionDate\":\"" + IsoTime(sessDate) + "\","
      "\"entryPrice\":" + DoubleToString(g_pos.entryPrice, 2) + ","
      "\"stopPrice\":"  + DoubleToString(g_pos.slPrice, 2) + ","
      "\"targetPrice\":" + DoubleToString(g_pos.tpPrice, 2) + ","
      "\"exitPrice\":"  + DoubleToString(exitPrice, 2) + ","
      "\"mfePoints\":"  + DoubleToString(g_pos.mfePts, 2) + ","
      "\"maePoints\":"  + DoubleToString(g_pos.maePts, 2) + ","
      "\"hit1R\":"      + BoolStr(g_pos.hit[1]) + ","
      "\"hit2R\":"      + BoolStr(g_pos.hit[2]) + ","
      "\"hit3R\":"      + BoolStr(g_pos.hit[3]) + ","
      "\"hit4R\":"      + BoolStr(g_pos.hit[4]) + ","
      "\"hit5R\":"      + BoolStr(g_pos.hit[5]) + ","
      "\"lotSize\":"    + DoubleToString(g_pos.lotSize, 2) + ","
      "\"slDist\":"     + DoubleToString(g_pos.slDist, 2) + ","
      "\"tpDist\":"     + DoubleToString(g_pos.tpDist, 2) + ","
      "\"capitalInicial\":" + DoubleToString(g_pos.capitalAtEntry, 2) + ","
      "\"riskPct\":"    + DoubleToString(g_riskPct, 1) + ","
      "\"pnlNet\":"     + DoubleToString(pnlNet, 2) + ","
      "\"durationMin\":" + IntegerToString(durationMin) + ","
      "\"rrAchieved\":"  + DoubleToString(resultR, 4) +
      "}";
   return j;
}

//+------------------------------------------------------------------+
//| SendTradeToApi                                                   |
//+------------------------------------------------------------------+
void SendTradeToApi(const string json)
{
   string headers = "Content-Type: application/json\r\nX-API-Key: " + ApiKey + "\r\n";
   uchar  dataArr[], resArr[];
   string resHeaders;

   StringToCharArray(json, dataArr, 0, StringLen(json));
   ResetLastError();
   int code = WebRequest("POST", ApiUrl, headers, 5000, dataArr, resArr, resHeaders);

   if(code == 201 || code == 200)
   {
      Print("[ReplayPanel] Trade enviado. HTTP ", code);
   }
   else
   {
      PrintFormat("[ReplayPanel] WebRequest falhou (code=%d err=%d) — salvando CSV", code, GetLastError());
      SaveFallbackCsv(json);
   }
}

//+------------------------------------------------------------------+
//| SaveFallbackCsv — uma linha JSON por trade (acumula sem truncar) |
//+------------------------------------------------------------------+
void SaveFallbackCsv(const string json)
{
   int h = FileOpen(FALLBACK_CSV, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { Print("[ReplayPanel] Falha ao abrir CSV fallback"); return; }
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, json + "\n");
   FileClose(h);
   Print("[ReplayPanel] Trade salvo em ", FALLBACK_CSV);
}

//+------------------------------------------------------------------+
//| ComputePostExitMaeMfe — varre ticks após saída (retroativo)      |
//+------------------------------------------------------------------+
void ComputePostExitMaeMfe(datetime exitTime)
{
   MqlTick postTicks[];
   ulong startMs = (ulong)exitTime * 1000UL;

   int copied = CopyTicks(SourceSymbol, postTicks, COPY_TICKS_ALL, startMs, 200000);
   if(copied <= 0) return;

   for(int i = 0; i < copied; i++)
   {
      double fav, adv;
      if(g_pos.direction == "LONG")
      {
         fav = postTicks[i].bid - g_pos.entryPrice;
         adv = g_pos.entryPrice - postTicks[i].bid;
      }
      else
      {
         fav = g_pos.entryPrice - postTicks[i].ask;
         adv = postTicks[i].ask - g_pos.entryPrice;
      }

      double favPts = fav / g_point;
      double advPts = adv / g_point;
      if(favPts > g_pos.mfePts) g_pos.mfePts = favPts;
      if(advPts > g_pos.maePts) g_pos.maePts = advPts;

      double slPts = g_pos.slDist / g_point;
      for(int r = 1; r <= 5; r++)
         if(!g_pos.hit[r] && g_pos.mfePts >= slPts * r)
            g_pos.hit[r] = true;
   }

   PrintFormat("[ReplayPanel] Pós-saída: MFE=%.1f pts MAE=%.1f pts | hit1R=%s hit2R=%s hit3R=%s",
               g_pos.mfePts, g_pos.maePts,
               BoolStr(g_pos.hit[1]), BoolStr(g_pos.hit[2]), BoolStr(g_pos.hit[3]));
}

//+------------------------------------------------------------------+
//| FlashPanel — fundo verde (WIN) ou vermelho (LOSS) por 2s         |
//+------------------------------------------------------------------+
void FlashPanel(bool win)
{
   g_flashEnd  = TimeCurrent() + 2;
   g_flashWin  = win;
   color c     = win ? CLR_WIN : CLR_LOSS;
   ObjectSetInteger(0, PRE "BG", OBJPROP_BGCOLOR, c);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| TakeScreenshot                                                   |
//+------------------------------------------------------------------+
void TakeScreenshot(const string prefix)
{
   string fname = "MQL5\\Files\\screenshots\\" + prefix + ".png";
   if(!ChartScreenShot(ChartID(), fname, 1920, 1080))
      PrintFormat("[ReplayPanel] Screenshot falhou: %s (err=%d)", fname, GetLastError());
}

//+------------------------------------------------------------------+
//| CreateHLine — cria ou recria uma linha horizontal                |
//+------------------------------------------------------------------+
void CreateHLine(const string name, double price, color clr, const string lbl)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetString (0, name, OBJPROP_TEXT,       lbl);
}

//+------------------------------------------------------------------+
//| DrawLines — SL, TP e entrada                                     |
//+------------------------------------------------------------------+
void DrawLines(double entry, double sl, double tp)
{
   CreateHLine(EN_LINE, entry, clrDodgerBlue, "Entrada");
   CreateHLine(SL_LINE, sl,    clrRed,        "SL");
   CreateHLine(TP_LINE, tp,    clrLime,        "TP");
}

//+------------------------------------------------------------------+
//| Helpers de criação de objetos de painel                          |
//+------------------------------------------------------------------+
void CreateRect(const string name, int x, int y, int w, int h, color clr)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateLabel(const string name, int x, int y, const string text,
                 color clr = CLR_TEXT, int fs = 9)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fs);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateBtn(const string name, int x, int y, int w, int h,
               const string text, color bgClr, color txtClr = CLR_TEXT)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bgClr);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     txtClr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  9);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, name, OBJPROP_STATE,     false);
}

void SetLabel(const string name, const string text, color clr = CLR_TEXT)
{
   ObjectSetString (0, name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void SetBtnBg(const string name, color clr)
{
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
}

//+------------------------------------------------------------------+
//| SyncLinesToOtherCharts — replica EN/SL/TP nos gráficos M5 e H1  |
//+------------------------------------------------------------------+
void SyncLinesToOtherCharts()
{
   if(!g_pos.isOpen) return;
   long currentChart = ChartID();
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(chartId != currentChart && ChartSymbol(chartId) == DestSymbol)
      {
         string lines[]  = { EN_LINE, SL_LINE, TP_LINE };
         color  colors[] = { clrDodgerBlue, clrRed, clrLime };
         string labels[] = { "Entrada", "SL", "TP" };
         double prices[] = { g_pos.entryPrice, g_pos.slPrice, g_pos.tpPrice };

         for(int i = 0; i < 3; i++)
         {
            ObjectDelete(chartId, lines[i]);
            ObjectCreate(chartId, lines[i], OBJ_HLINE, 0, 0, prices[i]);
            ObjectSetInteger(chartId, lines[i], OBJPROP_COLOR,      colors[i]);
            ObjectSetInteger(chartId, lines[i], OBJPROP_STYLE,      STYLE_DOT);
            ObjectSetInteger(chartId, lines[i], OBJPROP_WIDTH,      1);
            ObjectSetString (chartId, lines[i], OBJPROP_TEXT,       labels[i]);
            ObjectSetInteger(chartId, lines[i], OBJPROP_SELECTABLE, false);
         }
         ChartRedraw(chartId);
      }
      chartId = ChartNext(chartId);
   }
}

//+------------------------------------------------------------------+
//| RemoveLinesFromOtherCharts — limpa EN/SL/TP dos outros gráficos  |
//+------------------------------------------------------------------+
void RemoveLinesFromOtherCharts()
{
   long currentChart = ChartID();
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(chartId != currentChart && ChartSymbol(chartId) == DestSymbol)
      {
         ObjectDelete(chartId, EN_LINE);
         ObjectDelete(chartId, SL_LINE);
         ObjectDelete(chartId, TP_LINE);
         ChartRedraw(chartId);
      }
      chartId = ChartNext(chartId);
   }
}

//+------------------------------------------------------------------+
//| SyncManualObjects — replica objetos manuais do M15 nos outros    |
//+------------------------------------------------------------------+
void SyncManualObjects()
{
   long currentChart = ChartID();
   int total = ObjectsTotal(currentChart, 0);

   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(currentChart, i, 0);
      if(StringFind(name, PRE) == 0) continue;
      if(name == EN_LINE || name == SL_LINE || name == TP_LINE) continue;

      int      type  = (int)ObjectGetInteger(currentChart, name, OBJPROP_TYPE);
      datetime t1    = (datetime)ObjectGetInteger(currentChart, name, OBJPROP_TIME,  0);
      double   p1    = ObjectGetDouble(currentChart, name, OBJPROP_PRICE, 0);
      datetime t2    = (datetime)ObjectGetInteger(currentChart, name, OBJPROP_TIME,  1);
      double   p2    = ObjectGetDouble(currentChart, name, OBJPROP_PRICE, 1);
      color    clr   = (color)ObjectGetInteger(currentChart, name, OBJPROP_COLOR);
      int      style = (int)ObjectGetInteger(currentChart, name, OBJPROP_STYLE);
      int      width = (int)ObjectGetInteger(currentChart, name, OBJPROP_WIDTH);

      long chartId = ChartFirst();
      while(chartId >= 0)
      {
         if(chartId != currentChart && ChartSymbol(chartId) == DestSymbol)
         {
            if(ObjectFind(chartId, name) < 0)
               ObjectCreate(chartId, name, (ENUM_OBJECT)type, 0, t1, p1, t2, p2);
            ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr);
            ObjectSetInteger(chartId, name, OBJPROP_STYLE, style);
            ObjectSetInteger(chartId, name, OBJPROP_WIDTH, width);
            ChartRedraw(chartId);
         }
         chartId = ChartNext(chartId);
      }
   }

   // Remove objetos que foram deletados no M15
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(chartId != currentChart && ChartSymbol(chartId) == DestSymbol)
      {
         int otherTotal = ObjectsTotal(chartId, 0);
         for(int j = otherTotal - 1; j >= 0; j--)
         {
            string oName = ObjectName(chartId, j, 0);
            if(StringFind(oName, PRE) == 0) continue;
            if(oName == EN_LINE || oName == SL_LINE || oName == TP_LINE) continue;
            if(ObjectFind(currentChart, oName) < 0)
               ObjectDelete(chartId, oName);
         }
         ChartRedraw(chartId);
      }
      chartId = ChartNext(chartId);
   }
}

//+------------------------------------------------------------------+
//| PanelCreate — cria todos os objetos uma vez                      |
//+------------------------------------------------------------------+
void PanelCreate()
{
   int x = PX, y = PY;

   // Fundo principal
   CreateRect(PRE "BG", x, y, PW, PH, CLR_BG);

   // --- Linha 1: Capital
   CreateLabel(PRE "L_CAP_T",  x+8,  y+8,   "Capital",       CLR_MUTED, 8);
   CreateLabel(PRE "L_CAP_V",  x+8,  y+20,  "$0.00",         CLR_TEXT,  11);

   // --- Linha 2: Risco (+/-) | Lote
   CreateLabel(PRE "L_RSK_T",  x+8,  y+42,  "Risco",         CLR_MUTED, 8);
   CreateLabel(PRE "L_RSK_V",  x+8,  y+54,  "0.0%",          CLR_TEXT,  9);
   CreateBtn(PRE "RISK_DN",    x+52, y+51,  18, 16, "-",     CLR_BG2);
   CreateBtn(PRE "RISK_UP",    x+72, y+51,  18, 16, "+",     CLR_BG2);
   CreateLabel(PRE "L_LOT_T",  x+90, y+42,  "Lote",          CLR_MUTED, 8);
   CreateLabel(PRE "L_LOT_V",  x+90, y+54,  "0.00",          CLR_TEXT,  9);

   // --- Linha 3: SL | TP
   CreateLabel(PRE "L_SL_T",   x+8,  y+74,  "SL (dist)",     CLR_MUTED, 8);
   CreateLabel(PRE "L_SL_V",   x+8,  y+86,  "0.00",          CLR_TEXT,  9);
   CreateLabel(PRE "L_TP_T",   x+90, y+74,  "TP (dist)",     CLR_MUTED, 8);
   CreateLabel(PRE "L_TP_V",   x+90, y+86,  "0.00",          CLR_TEXT,  9);

   // --- Linha 4: PnL (só com posição)
   CreateLabel(PRE "L_PNL_T",  x+8,  y+106, "PnL",           CLR_MUTED, 8);
   CreateLabel(PRE "L_PNL_V",  x+8,  y+118, "—",             CLR_TEXT,  9);

   // --- Linha 5: Timer de próxima barra M15
   CreateLabel(PRE "L_TIMER_T", x+8, y+138, "Próxima barra", CLR_MUTED, 8);
   CreateLabel(PRE "L_TIMER_V", x+8, y+150, "00:00",         CLR_TEXT,  11);

   // Separador visual (faixa escura)
   CreateRect(PRE "SEP1", x, y+168, PW, 2, CLR_BG2);

   // --- Botões BUY / SELL
   CreateBtn(PRE "BUY",   x+6,   y+176, 108, 28, "▲  BUY",  CLR_BUY);
   CreateBtn(PRE "SELL",  x+122, y+176, 108, 28, "▼  SELL", CLR_SELL);

   // --- Botão FECHAR
   CreateBtn(PRE "CLOSE", x+6,   y+210, 224, 24, "FECHAR POSIÇÃO", CLR_CLOSE);

   CreateRect(PRE "SEP2", x, y+240, PW, 2, CLR_BG2);

   // --- Velocidade: label + 4 botões
   CreateLabel(PRE "L_SPD",    x+8,  y+246, "Velocidade",    CLR_MUTED, 8);
   CreateBtn(PRE "SPD1",  x+6,   y+258, 50, 22, "1x",  CLR_SPD_ON);
   CreateBtn(PRE "SPD2",  x+60,  y+258, 50, 22, "2x",  CLR_SPD_OFF);
   CreateBtn(PRE "SPD4",  x+114, y+258, 50, 22, "4x",  CLR_SPD_OFF);
   CreateBtn(PRE "SPD8",  x+168, y+258, 62, 22, "8x",  CLR_SPD_OFF);

   CreateRect(PRE "SEP3", x, y+286, PW, 2, CLR_BG2);

   // --- Botão PAUSE/PLAY
   CreateBtn(PRE "PAUSE", x+6,  y+294, 224, 28, "❚❚  PAUSAR",  CLR_PAUSE);

   // --- Rodapé: símbolo
   CreateLabel(PRE "L_SYM", x+8, y+332, DestSymbol, CLR_MUTED, 8);

}

//+------------------------------------------------------------------+
//| PanelDelete — preserva linhas SL/TP/Entry                        |
//+------------------------------------------------------------------+
void PanelDelete()
{
   string panelObjs[] = {
      PRE "BG", PRE "L_CAP_T", PRE "L_CAP_V", PRE "L_RSK_T", PRE "L_RSK_V",
      PRE "L_LOT_T", PRE "L_LOT_V", PRE "L_SL_T", PRE "L_SL_V",
      PRE "L_TP_T", PRE "L_TP_V", PRE "L_PNL_T", PRE "L_PNL_V",
      PRE "SEP1", PRE "SEP2", PRE "SEP3",
      PRE "BUY", PRE "SELL", PRE "CLOSE", PRE "PAUSE",
      PRE "SPD1", PRE "SPD2", PRE "SPD4", PRE "SPD8",
      PRE "L_SPD", PRE "L_SYM", PRE "L_TIMER_T", PRE "L_TIMER_V",
      PRE "RISK_UP", PRE "RISK_DN"
   };
   for(int i = 0; i < ArraySize(panelObjs); i++)
      ObjectDelete(0, panelObjs[i]);
}

//+------------------------------------------------------------------+
//| PanelUpdate — atualiza textos sem recriar objetos                |
//+------------------------------------------------------------------+
void PanelUpdate()
{
   // Capital
   SetLabel(PRE "L_CAP_V", StringFormat("$%.2f", g_capital));

   // Risco e lote (usa slDist atual)
   double sl  = g_pos.isOpen ? g_pos.slDist : g_slDist;
   double tp  = g_pos.isOpen ? g_pos.tpDist : g_tpDist;
   double lot = CalcLot(sl);
   SetLabel(PRE "L_RSK_V", StringFormat("%.1f%%", g_riskPct));
   SetLabel(PRE "L_LOT_V", StringFormat("%.2f", lot));

   // SL / TP
   SetLabel(PRE "L_SL_V", StringFormat("%.2f", sl));
   SetLabel(PRE "L_TP_V", StringFormat("%.2f", tp));

   // PnL flutuante
   if(g_pos.isOpen)
   {
      MqlTick t;
      if(SymbolInfoTick(DestSymbol, t))
      {
         double ep  = (g_pos.direction == "LONG") ? t.bid : t.ask;
         double pnl = CalcPnl(ep);
         double r   = (g_pos.riskUsd > 0) ? pnl / g_pos.riskUsd : 0;
         color  clr = (pnl >= 0) ? clrLime : clrTomato;
         SetLabel(PRE "L_PNL_V",
                  StringFormat("$%.2f  (%.2fR)", pnl, r), clr);
      }
      // Mostrar botão FECHAR
      ObjectSetInteger(0, PRE "CLOSE", OBJPROP_BGCOLOR, CLR_SELL);
   }
   else
   {
      SetLabel(PRE "L_PNL_V", "—", CLR_MUTED);
      ObjectSetInteger(0, PRE "CLOSE", OBJPROP_BGCOLOR, CLR_CLOSE);
   }

   // Velocidade
   string speedNames[] = { PRE "SPD1", PRE "SPD2", PRE "SPD4", PRE "SPD8" };
   int    speedVals[]  = { 1, 2, 4, 8 };
   for(int i=0; i<4; i++)
      SetBtnBg(speedNames[i], (g_speed == speedVals[i]) ? CLR_SPD_ON : CLR_SPD_OFF);

   // Pause/Play
   ObjectSetString (0, PRE "PAUSE", OBJPROP_TEXT,    g_paused ? "▶  RETOMAR" : "❚❚  PAUSAR");
   ObjectSetInteger(0, PRE "PAUSE", OBJPROP_BGCOLOR, g_paused ? CLR_SPD_ON  : CLR_PAUSE);

   // Timer de próxima barra M15
   MqlTick tNow;
   if(SymbolInfoTick(DestSymbol, tNow))
   {
      datetime barOpen  = (datetime)((long)tNow.time / 900 * 900);
      datetime barClose = barOpen + 900;
      int secsLeft      = (int)(barClose - tNow.time);
      if(secsLeft < 0) secsLeft = 0;
      SetLabel(PRE "L_TIMER_V", StringFormat("%02d:%02d", secsLeft/60, secsLeft%60));
   }

   ChartRedraw();
}
//+------------------------------------------------------------------+
