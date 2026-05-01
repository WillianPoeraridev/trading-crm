//+------------------------------------------------------------------+
//|                                                ReplayEngine.mq5 |
//|                Replay de ticks históricos do NAS100 (Fusion)    |
//+------------------------------------------------------------------+
#property service
#property copyright "Trading CRM"
#property version   "1.00"
#property description "Replay de ticks históricos do NAS100 em símbolo custom NAS100_SIM"

//--- Inputs configuráveis
input string   SourceSymbol      = "NAS100";      // símbolo de origem (Fusion Markets)
input string   DestSymbol        = "NAS100_SIM";  // símbolo custom de destino
input datetime SessionDate = D'1970.01.02 00:00:00'; // data do replay (deixe 02/01/1970 = última usada)
input datetime EndDate     = D'1970.01.02 00:00:00'; // data final (deixe 02/01/1970 = fim do dia)
input int      OpeningHour       = 16;            // 16 (padrão) ou 15 (horário verão US)
input int      OpeningMinute     = 15;
input double   ContractSize      = 1.0;           // tamanho do contrato (Fusion: 1.0)
input double   TickValue         = 0.01;          // valor do tick em moeda de lucro (Fusion NAS100: 0.01 → $1/ponto/lote)
input double   TickSize          = 0.01;          // tamanho do tick (Fusion: 0.01)
input int      Digits_           = 2;             // dígitos do símbolo
input string   ProfitCurrency    = "USD";
input string   BaseCurrency      = "USD";
input string   MarginCurrency    = "USD";
input int      SpeedDefault      = 1;             // 1, 2, 4, 8, 16 ou 32
input int      MaxTicksPerDay    = 500000;        // capacidade do buffer de ticks
input int      AtrPeriod         = 10;            // período do ATR
input ENUM_TIMEFRAMES AtrTimeframe = PERIOD_M15;  // timeframe do ATR
input bool     LogTickValidation = false;         // loga validação OHLC por barra ao sintetizar

//--- Arquivos de comunicação com o painel (EA)
#define CMD_FILE "replay_cmd.txt"
#define ATR_FILE "replay_atr.txt"
#define STATUS_FILE "replay_status.txt"

//--- Estado global do replay
MqlTick g_ticks[];
int     g_total      = 0;
int     g_cursor     = 0;
int     g_speed      = 1;
bool    g_paused     = false;
bool    g_stopped    = false;
datetime g_startTime = 0;
datetime g_endTime   = 0;

//--- Modo SKIP_TO_BAR_END
bool     g_skipToBarEnd   = false;
datetime g_skipTargetTime = 0;
int      g_savedSpeed     = 1;

//+------------------------------------------------------------------+
//| OnStart                                                          |
//+------------------------------------------------------------------+
void OnStart()
{
   g_speed = (SpeedDefault==1 || SpeedDefault==2 || SpeedDefault==4 || SpeedDefault==8 || SpeedDefault==16 || SpeedDefault==32) ? SpeedDefault : 1;

   if(!EnsureCustomSymbol())
   {
      PrintFormat("[ReplayEngine] Falha ao criar/preparar símbolo custom %s", DestSymbol);
      return;
   }

   if(!SymbolSelect(DestSymbol, true))
      PrintFormat("[ReplayEngine] Aviso: não foi possível adicionar %s ao Market Watch", DestSymbol);

   // Limpa TODO o histórico existente do custom symbol (sessões anteriores)
   // Ticks devem ser deletados primeiro — CustomTicksDelete remove as barras correspondentes automaticamente
   long deletedTicks = CustomTicksDelete(DestSymbol, 0, LONG_MAX);
   long deletedBars  = CustomRatesDelete(DestSymbol, 0, LONG_MAX);
   PrintFormat("[ReplayEngine] Histórico anterior limpo: %d ticks, %d barras removidos",
               deletedTicks, deletedBars);

   // Persistência da última data usada
   datetime effectiveSession;
   // Sentinel: qualquer data antes de 2000 = "usar padrão"
   bool sessionIsDefault = (SessionDate < D'2000.01.01');

   if(sessionIsDefault)
   {
      if(GlobalVariableCheck("replay_last_session"))
         effectiveSession = (datetime)GlobalVariableGet("replay_last_session");
      else
         effectiveSession = D'2026.04.01 00:00:00';
   }
   else
      effectiveSession = SessionDate;

   g_startTime = ComputeStartTime(effectiveSession);
   GlobalVariableSet("replay_last_session", (double)effectiveSession);
   PrintFormat("[ReplayEngine] Sessão: %s (origem: %s)",
               TimeToString(effectiveSession, TIME_DATE),
               sessionIsDefault ? "GlobalVariable" : "input");

   PrintFormat("[ReplayEngine] Início do replay: %s (epoch %I64d)", TimeToString(g_startTime, TIME_DATE|TIME_SECONDS), (long)g_startTime);

   LoadHistoricalBars();

   // Garante que não há ticks futuros ao início do replay
   CustomTicksDelete(DestSymbol, (long)g_startTime * 1000, LONG_MAX);
   CustomRatesDelete(DestSymbol, g_startTime, LONG_MAX);
   Print("[ReplayEngine] Dados futuros ao replay removidos");

   if(!LoadTicks(g_startTime))
   {
      PrintFormat("[ReplayEngine] Falha ao carregar ticks de %s", SourceSymbol);
      return;
   }

   ComputeAndExportAtr();
   WriteStatus("READY");

   PrintFormat("[ReplayEngine] %d ticks carregados. Iniciando loop de replay (speed=%dx, paused=false)", g_total, g_speed);

   ReplayLoop();

   WriteStatus("FINISHED");
   PrintFormat("[ReplayEngine] Replay finalizado em cursor=%d/%d", g_cursor, g_total);
}

//+------------------------------------------------------------------+
//| Garante criação do símbolo custom clonando propriedades          |
//+------------------------------------------------------------------+
bool EnsureCustomSymbol()
{
   if(!SymbolSelect(SourceSymbol, true))
   {
      PrintFormat("[ReplayEngine] Símbolo origem %s não encontrado no Market Watch", SourceSymbol);
      return false;
   }

   if(!SymbolInfoInteger(DestSymbol, SYMBOL_CUSTOM))
   {
      if(!CustomSymbolCreate(DestSymbol, "Custom\\Replay", SourceSymbol))
      {
         PrintFormat("[ReplayEngine] CustomSymbolCreate falhou: %d", GetLastError());
         return false;
      }
      PrintFormat("[ReplayEngine] Símbolo custom %s criado", DestSymbol);
   }

   //--- Propriedades clonadas / configuráveis
   CustomSymbolSetInteger(DestSymbol, SYMBOL_DIGITS,             Digits_);
   CustomSymbolSetDouble (DestSymbol, SYMBOL_POINT,              TickSize);
   CustomSymbolSetDouble (DestSymbol, SYMBOL_TRADE_TICK_SIZE,    TickSize);
   CustomSymbolSetDouble (DestSymbol, SYMBOL_TRADE_TICK_VALUE,   TickValue);
   CustomSymbolSetDouble (DestSymbol, SYMBOL_TRADE_CONTRACT_SIZE, ContractSize);
   CustomSymbolSetInteger(DestSymbol, SYMBOL_TRADE_CALC_MODE,    SYMBOL_CALC_MODE_CFD);
   CustomSymbolSetInteger(DestSymbol, SYMBOL_CHART_MODE,         SYMBOL_CHART_MODE_BID);
   CustomSymbolSetString (DestSymbol, SYMBOL_CURRENCY_BASE,      BaseCurrency);
   CustomSymbolSetString (DestSymbol, SYMBOL_CURRENCY_PROFIT,    ProfitCurrency);
   CustomSymbolSetString (DestSymbol, SYMBOL_CURRENCY_MARGIN,    MarginCurrency);
   CustomSymbolSetString (DestSymbol, SYMBOL_DESCRIPTION,        "NAS100 Replay (sim)");

   return true;
}

//+------------------------------------------------------------------+
//| Calcula o timestamp de início ajustado para o horário configurado|
//+------------------------------------------------------------------+
datetime ComputeStartTime(datetime base)
{
   datetime b = (base == 0) ? TimeCurrent() : base;
   MqlDateTime dt;
   TimeToStruct(b, dt);
   dt.hour = OpeningHour;
   dt.min  = OpeningMinute;
   dt.sec  = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Copia barras M1 dos últimos 30 dias do símbolo de origem e      |
//| insere no custom symbol para dar contexto histórico ao gráfico  |
//+------------------------------------------------------------------+
bool LoadHistoricalBars()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, false);

   datetime from = g_startTime - (30 * 86400); // 30 dias antes do replay
   datetime to   = g_startTime - 60;            // exclui a barra das 16:15 (será criada via ticks)

   // Força sincronização do histórico M1 do source antes de copiar
   // (Fusion pode não ter o dia atual baixado no cache local)
   datetime syncFirst = 0;
   int syncTries = 0;
   while(syncTries < 10)
   {
      if(SeriesInfoInteger(SourceSymbol, PERIOD_M1, SERIES_FIRSTDATE, syncFirst) && syncFirst > 0 && syncFirst <= from)
         break;
      Sleep(200);
      syncTries++;
   }
   PrintFormat("[ReplayEngine] Sync histórico M1 de %s: tries=%d, FIRSTDATE=%s",
               SourceSymbol, syncTries,
               (syncFirst > 0 ? TimeToString(syncFirst, TIME_DATE|TIME_MINUTES) : "n/d"));

   int copied = CopyRates(SourceSymbol, PERIOD_M1, from, to, rates);
   if(copied <= 0)
   {
      PrintFormat("[ReplayEngine] CopyRates falhou (copied=%d, erro=%d)", copied, GetLastError());
      return false;
   }

   // Diagnóstico: quantas barras pertencem ao dia do replay (antes de g_startTime)
   MqlDateTime mdt;
   TimeToStruct(g_startTime, mdt);
   datetime dayStart = StructToTime(mdt) - mdt.hour * 3600 - mdt.min * 60 - mdt.sec;
   int barsOnReplayDay = 0;
   datetime firstBarOfDay = 0, lastBarOfDay = 0;
   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time >= dayStart && rates[i].time < g_startTime)
      {
         if(firstBarOfDay == 0) firstBarOfDay = rates[i].time;
         lastBarOfDay = rates[i].time;
         barsOnReplayDay++;
      }
   }
   PrintFormat("[ReplayEngine] Diagnóstico: %d barras totais, %d do dia do replay (de %s até %s)",
               copied, barsOnReplayDay,
               (firstBarOfDay > 0 ? TimeToString(firstBarOfDay, TIME_DATE|TIME_MINUTES) : "nenhuma"),
               (lastBarOfDay  > 0 ? TimeToString(lastBarOfDay,  TIME_DATE|TIME_MINUTES) : "nenhuma"));

   int added = CustomRatesUpdate(DestSymbol, rates);
   PrintFormat("[ReplayEngine] %d barras M1 históricas inseridas no %s (de %s até %s)",
               added, DestSymbol,
               TimeToString(rates[0].time, TIME_DATE|TIME_MINUTES),
               TimeToString(rates[copied-1].time, TIME_DATE|TIME_MINUTES));
   return added > 0;
}

//+------------------------------------------------------------------+
//| Estrutura para padrão de pontos de referência                    |
//+------------------------------------------------------------------+
struct PatternPoints
{
   int opening_shadow;
   int body;
   int closing_shadow;
};

//+------------------------------------------------------------------+
//| Seleciona padrão de referência baseado no tick_volume            |
//| Replica a tabela do algoritmo "Every tick" do Strategy Tester    |
//+------------------------------------------------------------------+
PatternPoints SelectReferencePattern(long tickVolume)
{
   PatternPoints pp;
   if(tickVolume <= 4)        { pp.opening_shadow=1; pp.body=1; pp.closing_shadow=1; }
   else if(tickVolume <= 6)   { pp.opening_shadow=1; pp.body=2; pp.closing_shadow=1; }
   else if(tickVolume <= 8)   { pp.opening_shadow=1; pp.body=3; pp.closing_shadow=1; }
   else if(tickVolume <= 11)  { pp.opening_shadow=1; pp.body=4; pp.closing_shadow=1; }
   else if(tickVolume <= 15)  { pp.opening_shadow=2; pp.body=3; pp.closing_shadow=2; }
   else if(tickVolume <= 25)  { pp.opening_shadow=2; pp.body=4; pp.closing_shadow=2; }
   else if(tickVolume <= 50)  { pp.opening_shadow=2; pp.body=5; pp.closing_shadow=2; }
   else if(tickVolume <= 100) { pp.opening_shadow=2; pp.body=6; pp.closing_shadow=2; }
   else                       { pp.opening_shadow=3; pp.body=5; pp.closing_shadow=3; }
   return pp;
}

//+------------------------------------------------------------------+
//| Realoca pontos de sombras ausentes para o corpo                  |
//+------------------------------------------------------------------+
void ReallocateMissingShadows(const MqlRates &bar, bool bullish, PatternPoints &pp)
{
   // Para bullish (O→L→H→C): sombra de abertura = entre O e L, sombra de fechamento = entre H e C
   // Para bearish (O→H→L→C): sombra de abertura = entre O e H, sombra de fechamento = entre L e C
   bool openingShadowMissing, closingShadowMissing;
   if(bullish)
   {
      openingShadowMissing = (bar.low  >= bar.open  - TickSize * 0.5);
      closingShadowMissing = (bar.high <= bar.close + TickSize * 0.5);
   }
   else
   {
      openingShadowMissing = (bar.high <= bar.open  + TickSize * 0.5);
      closingShadowMissing = (bar.low  >= bar.close - TickSize * 0.5);
   }

   if(openingShadowMissing) { pp.body += pp.opening_shadow; pp.opening_shadow = 0; }
   if(closingShadowMissing) { pp.body += pp.closing_shadow; pp.closing_shadow = 0; }
}

//+------------------------------------------------------------------+
//| Gera pontos de corpo com ondas de impulso (não-linear)           |
//| Replica o algoritmo "saw-tooth" do MT5 Strategy Tester           |
//+------------------------------------------------------------------+
int GenerateBodyPoints(double low, double high, int nPoints, bool ascending,
                       double point, double &outPrices[])
{
   if(nPoints <= 0 || high <= low + point * 0.5)
      return 0;

   // Trabalha em pontos inteiros para evitar drift de ponto flutuante
   long loP = (long)MathRound(low  / point);
   long hiP = (long)MathRound(high / point);
   long rangeP = hiP - loP;
   if(rangeP < 1) return 0;

   int waves = (nPoints + 1) / 2;
   long step = rangeP / MathMax(waves, 1);
   if(step < 1) step = 1;

   long sign = ascending ? +1 : -1;
   long prev = ascending ? loP : hiP;

   int written = 0;
   for(int w = 0; w < waves && written < nPoints; w++)
   {
      long n1 = prev + sign * step;
      // Clamp ao range
      if(n1 < loP) n1 = loP;
      if(n1 > hiP) n1 = hiP;

      if(written < nPoints)
         outPrices[written++] = n1 * point;

      if(written < nPoints)
      {
         long n2 = n1 - sign;  // recua 1 ponto (cria oscilação)
         if(n2 < loP) n2 = loP;
         if(n2 > hiP) n2 = hiP;
         outPrices[written++] = n2 * point;
         prev = n2;
      }
      else
         prev = n1;
   }

   // Garante que o ponto final chega ao extremo correto
   if(written > 0)
      outPrices[written - 1] = ascending ? high : low;

   return written;
}

//+------------------------------------------------------------------+
//| Interpola entre dois pontos com saw-tooth ou linear              |
//+------------------------------------------------------------------+
int InterpolateBetweenPoints(double p1, double p2, int nIntermediate,
                             double barLow, double barHigh, double point,
                             double &outPrices[])
{
   if(nIntermediate <= 0)
      return 0;

   double range = MathAbs(p2 - p1);
   // Amplitude do saw-tooth: 15% do range entre os pontos, mínimo 1 tick
   double amplitude = MathMax(point, range * 0.15 / MathMax(nIntermediate, 1));
   bool useSawtooth = (nIntermediate >= 2);

   for(int k = 1; k <= nIntermediate; k++)
   {
      double t = (double)k / (nIntermediate + 1);
      double linear = p1 + (p2 - p1) * t;
      double price;

      if(useSawtooth)
      {
         double offset = amplitude * ((k % 2 == 0) ? +1.0 : -1.0);
         price = linear + offset;
      }
      else
         price = linear;

      // Clamp duro ao OHLC da barra
      price = MathMax(barLow, MathMin(barHigh, price));
      // Normaliza ao tick size
      price = MathRound(price / point) * point;
      outPrices[k - 1] = price;
   }
   return nIntermediate;
}

//+------------------------------------------------------------------+
//| Emite 1 tick garantindo monotonia de time_msc                    |
//+------------------------------------------------------------------+
void EmitTickAt(int idx, long timeMs, double price, double spreadPrice, long &prevMsc)
{
   if(timeMs <= prevMsc) timeMs = prevMsc + 1;
   g_ticks[idx].time     = (datetime)(timeMs / 1000);
   g_ticks[idx].time_msc = timeMs;
   g_ticks[idx].bid      = price;
   g_ticks[idx].ask      = price + spreadPrice;
   g_ticks[idx].last     = price;
   g_ticks[idx].flags    = TICK_FLAG_BID | TICK_FLAG_ASK;
   prevMsc = timeMs;
}

//+------------------------------------------------------------------+
//| Jitter temporal: ±20% do intervalo médio (mantém monotonia)      |
//+------------------------------------------------------------------+
long CalcJitter(long avgInterval)
{
   double r = ((double)MathRand() / 32767.0) * 2.0 - 1.0;  // [-1, +1]
   return (long)(r * avgInterval * 0.20);
}

//+------------------------------------------------------------------+
//| Valida invariantes OHLC por barra na saída sintetizada           |
//+------------------------------------------------------------------+
void ValidateSynthOutput(MqlRates &rates[], int count, int firstIdx, int lastIdx, double point)
{
   if(!LogTickValidation) return;

   int ok = 0, fail = 0;
   int tickIdx = firstIdx;

   for(int i = 0; i < count && tickIdx <= lastIdx; i++)
   {
      double O = rates[i].open, H = rates[i].high, L = rates[i].low, C = rates[i].close;
      double tol = point * 1.5;

      // Encontra ticks desta barra
      datetime barStart = rates[i].time;
      datetime barEnd   = (i + 1 < count) ? rates[i+1].time : barStart + 86400;

      double minBid = DBL_MAX, maxBid = -DBL_MAX;
      double firstBid = -1, lastBid = -1;

      while(tickIdx <= lastIdx && g_ticks[tickIdx].time < barEnd)
      {
         double b = g_ticks[tickIdx].bid;
         if(firstBid < 0) firstBid = b;
         lastBid = b;
         if(b < minBid) minBid = b;
         if(b > maxBid) maxBid = b;
         tickIdx++;
      }

      if(firstBid < 0) continue;

      bool passed = (MathAbs(firstBid - O) <= tol) &&
                    (MathAbs(lastBid  - C) <= tol) &&
                    (MathAbs(maxBid   - H) <= tol) &&
                    (MathAbs(minBid   - L) <= tol);
      if(passed) ok++;
      else
      {
         fail++;
         PrintFormat("[Validate] FALHOU barra %s: O=%.2f(got%.2f) H=%.2f(got%.2f) L=%.2f(got%.2f) C=%.2f(got%.2f)",
                     TimeToString(barStart, TIME_DATE|TIME_MINUTES),
                     O, firstBid, H, maxBid, L, minBid, C, lastBid);
      }
   }

   PrintFormat("[ReplayEngine] Validação: %d/%d barras OK (%d falhas)", ok, ok+fail, fail);
}

//+------------------------------------------------------------------+
//| Sintetiza ticks a partir de barras OHLC                          |
//| Algoritmo: replica o "Every tick" do MT5 Strategy Tester         |
//| (11 pontos de referência, ondas de impulso, saw-tooth)           |
//+------------------------------------------------------------------+
bool SynthesizeTicks(MqlRates &rates[], int count, int barSecs, ENUM_TIMEFRAMES tf)
{
   double point       = SymbolInfoDouble(SourceSymbol, SYMBOL_POINT);
   if(point <= 0) point = TickSize;
   long   spreadPts   = SymbolInfoInteger(SourceSymbol, SYMBOL_SPREAD);
   double spreadPrice = (spreadPts > 0) ? spreadPts * point : TickSize;

   const int MAX_TICKS_PER_BAR = 2000;

   // Estimativa de ticks totais usando tick_volume real das barras.
   // Mínimo de 20 por barra para cobrir os âncoras (padrão 3-5-3 = 15 pts + intermediários).
   long totalEstimate = 0;
   for(int i = 0; i < count; i++)
   {
      long tv = rates[i].tick_volume;
      if(tv < 20)  tv = 20;
      if(tv > MAX_TICKS_PER_BAR) tv = MAX_TICKS_PER_BAR;
      totalEstimate += tv;
   }
   if(totalEstimate <= 0) totalEstimate = count * 20;
   if(totalEstimate > MaxTicksPerDay) totalEstimate = MaxTicksPerDay;

   ArrayResize(g_ticks, (int)totalEstimate);
   ArraySetAsSeries(g_ticks, false);

   int  idx    = 0;
   long prevMsc = 0;
   int  firstIdx = 0;

   for(int i = 0; i < count; i++)
   {
      if(idx >= MaxTicksPerDay) { PrintFormat("[ReplayEngine] Buffer MaxTicksPerDay atingido na barra %d", i); break; }
      // Garante espaço para mais 2000 ticks (1 barra inteira no pior caso)
      if(idx + MAX_TICKS_PER_BAR + 20 > ArraySize(g_ticks))
         ArrayResize(g_ticks, MathMin(idx + MAX_TICKS_PER_BAR + 20, MaxTicksPerDay));

      MqlRates bar      = rates[i];
      long barStartMs   = (long)bar.time * 1000LL;
      long nTicksBar    = bar.tick_volume;
      if(nTicksBar <= 0) { PrintFormat("[ReplayEngine] Aviso: tick_volume=0 na barra %s — usando 1", TimeToString(bar.time, TIME_DATE|TIME_MINUTES)); nTicksBar = 1; }
      if(nTicksBar > MAX_TICKS_PER_BAR) nTicksBar = MAX_TICKS_PER_BAR;

      // ---- Casos especiais ----
      if(nTicksBar == 1)
      {
         EmitTickAt(idx++, barStartMs + barSecs * 1000LL - 1, bar.close, spreadPrice, prevMsc);
         continue;
      }
      if(nTicksBar == 2)
      {
         EmitTickAt(idx++, barStartMs,                         bar.open,  spreadPrice, prevMsc);
         EmitTickAt(idx++, barStartMs + barSecs * 1000LL - 1, bar.close, spreadPrice, prevMsc);
         continue;
      }

      // ---- Direção ----
      bool bullish;
      if(bar.close > bar.open)      bullish = true;
      else if(bar.close < bar.open) bullish = false;
      else  // doji: inverte a direção da barra anterior
         bullish = (i > 0) ? (rates[i-1].close < rates[i-1].open) : true;

      // ---- Pontos de referência ----
      PatternPoints pp = SelectReferencePattern(nTicksBar);
      ReallocateMissingShadows(bar, bullish, pp);

      // ---- Constrói sequência de âncoras ----
      // Bullish: O → [shadow_pts] → L → [body_pts] → H → [shadow_pts] → C
      // Bearish: O → [shadow_pts] → H → [body_pts] → L → [shadow_pts] → C
      double anchors[];
      int maxAnchors = 4 + pp.opening_shadow + pp.body + pp.closing_shadow;
      ArrayResize(anchors, maxAnchors);
      int a = 0;

      anchors[a++] = bar.open;

      double ext1 = bullish ? bar.low  : bar.high;  // primeiro extremo após open
      double ext2 = bullish ? bar.high : bar.low;   // segundo extremo antes de close

      // Sombra de abertura (linear entre open e ext1)
      for(int k = 1; k <= pp.opening_shadow; k++)
         anchors[a++] = bar.open + (ext1 - bar.open) * (double)k / (pp.opening_shadow + 1);

      anchors[a++] = ext1;

      // Corpo (ondas de impulso entre ext1 e ext2)
      if(pp.body > 0)
      {
         double bodyPts[];
         ArrayResize(bodyPts, pp.body);
         int n = GenerateBodyPoints(bar.low, bar.high, pp.body, bullish, point, bodyPts);
         for(int k = 0; k < n; k++)
            anchors[a++] = bodyPts[k];
      }

      anchors[a++] = ext2;

      // Sombra de fechamento (linear entre ext2 e close)
      for(int k = 1; k <= pp.closing_shadow; k++)
         anchors[a++] = ext2 + (bar.close - ext2) * (double)k / (pp.closing_shadow + 1);

      anchors[a++] = bar.close;
      int nAnchors = a;

      // ---- Distribui ticks intermediários entre segmentos ----
      long ticksRem = nTicksBar - nAnchors;
      if(ticksRem < 0) ticksRem = 0;
      int segCount  = nAnchors - 1;
      int perSegBase  = (segCount > 0) ? (int)(ticksRem / segCount) : 0;
      int perSegExtra = (segCount > 0) ? (int)(ticksRem % segCount) : 0;

      long avgIntervalMs = (nTicksBar > 0) ? ((long)barSecs * 1000LL / nTicksBar) : 1000LL;
      if(avgIntervalMs < 1) avgIntervalMs = 1;

      long localCursor = barStartMs;

      for(int s = 0; s < segCount; s++)
      {
         if(idx >= MaxTicksPerDay) break;

         double p1 = anchors[s];
         double p2 = anchors[s + 1];
         int nInter = perSegBase + (s < perSegExtra ? 1 : 0);

         // Emite âncora s (exceto na segunda iteração em diante, pois já foi emitida como p2 anterior)
         if(s == 0)
         {
            EmitTickAt(idx++, localCursor, p1, spreadPrice, prevMsc);
            localCursor += avgIntervalMs + CalcJitter(avgIntervalMs);
         }

         // Ticks intermediários
         if(nInter > 0)
         {
            double interBuf[];
            ArrayResize(interBuf, nInter);
            int got = InterpolateBetweenPoints(p1, p2, nInter, bar.low, bar.high, point, interBuf);
            for(int k = 0; k < got && idx < MaxTicksPerDay; k++)
            {
               long jitter = CalcJitter(avgIntervalMs);
               EmitTickAt(idx++, localCursor + jitter, interBuf[k], spreadPrice, prevMsc);
               localCursor += avgIntervalMs;
            }
         }

         // Emite âncora s+1 (= p2)
         if(idx < MaxTicksPerDay)
         {
            // Último segmento: cravar o close exatamente no fim da barra
            long ts = (s == segCount - 1)
                      ? (barStartMs + (long)barSecs * 1000LL - 1)
                      : (localCursor + CalcJitter(avgIntervalMs));
            EmitTickAt(idx++, ts, p2, spreadPrice, prevMsc);
            localCursor += avgIntervalMs;
         }
      }
   }

   g_total = idx;
   ArrayResize(g_ticks, g_total);
   PrintFormat("[ReplayEngine] Sintetizados %d ticks a partir de %d barras %s (algoritmo MT5 Every-Tick)",
               g_total, count, EnumToString(tf));

   ValidateSynthOutput(rates, count, firstIdx, g_total - 1, point);
   return g_total > 0;
}

//+------------------------------------------------------------------+
//| Fallback adaptativo: tenta M1 → M5 → M15 → H1 até achar dados    |
//+------------------------------------------------------------------+
bool LoadTicksFromBars(datetime startTime)
{
   ENUM_TIMEFRAMES tfs[4]  = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1 };
   int             secs[4] = { 60,        300,       900,        3600      };

   for(int k = 0; k < 4; k++)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, false);
      ResetLastError();
      int copied = CopyRates(SourceSymbol, tfs[k], startTime, g_endTime, rates);
      if(copied > 0)
      {
         PrintFormat("[ReplayEngine] Fallback OK em %s: %d barras no intervalo",
                     EnumToString(tfs[k]), copied);
         return SynthesizeTicks(rates, copied, secs[k], tfs[k]);
      }
      PrintFormat("[ReplayEngine] %s vazio (erro=%d), tentando timeframe maior...",
                  EnumToString(tfs[k]), GetLastError());
   }

   PrintFormat("[ReplayEngine] FALHA: nenhum timeframe (M1/M5/M15/H1) tem dados para %s",
               TimeToString(startTime, TIME_DATE));
   return false;
}

//+------------------------------------------------------------------+
//| Carrega ticks do dia a partir do startTime                       |
//+------------------------------------------------------------------+
bool LoadTicks(datetime startTime)
{
   // Calcular g_endTime PRIMEIRO para delimitar a janela do CopyTicksRange
   bool endIsDefault = (EndDate < D'2000.01.01');
   if(!endIsDefault && EndDate > g_startTime)
      g_endTime = EndDate;
   else
      g_endTime = (datetime)((long)g_startTime / 86400 * 86400 + 86400);

   ulong startMs = (ulong)startTime * 1000UL;
   ulong endMs   = (ulong)g_endTime  * 1000UL;

   // Prime tick cache — força o terminal a baixar a faixa do servidor antes da cópia definitiva
   MqlTick primer[];
   int primerTries = 0;
   while(primerTries < 25)
   {
      ResetLastError();
      int probe = CopyTicksRange(SourceSymbol, primer, COPY_TICKS_ALL, startMs, startMs + 60000UL);
      if(probe > 0) break;
      Sleep(200);
      primerTries++;
   }
   PrintFormat("[ReplayEngine] Tick sync: %d tentativa(s) (último erro=%d)", primerTries, GetLastError());

   ArrayResize(g_ticks, MaxTicksPerDay);
   ArraySetAsSeries(g_ticks, false);

   ResetLastError();
   int copied = CopyTicksRange(SourceSymbol, g_ticks, COPY_TICKS_ALL, startMs, endMs);
   if(copied <= 0)
   {
      PrintFormat("[ReplayEngine] Broker sem ticks para %s → %s (erro=%d). Tentando fallback M1...",
                  TimeToString(startTime, TIME_DATE|TIME_SECONDS),
                  TimeToString(g_endTime, TIME_DATE|TIME_SECONDS),
                  GetLastError());
      return LoadTicksFromBars(startTime);
   }
   g_total = copied;
   ArrayResize(g_ticks, g_total);
   PrintFormat("[ReplayEngine] %d ticks no intervalo %s → %s",
               g_total,
               TimeToString(startTime, TIME_DATE|TIME_SECONDS),
               TimeToString(g_endTime, TIME_DATE|TIME_SECONDS));
   return true;
}

//+------------------------------------------------------------------+
//| Loop principal de replay                                         |
//+------------------------------------------------------------------+
void ReplayLoop()
{
   while(!IsStopped() && !g_stopped && g_cursor < g_total)
   {
      ProcessCommandFile();

      if(g_paused)
      {
         WriteStatus("PAUSED");
         Sleep(100);
         continue;
      }

      MqlTick t = g_ticks[g_cursor];

      //--- ajusta time_msc / time para preservar microestrutura
      ResetLastError();
      MqlTick tickArr[1];
      tickArr[0] = t;
      int added = CustomTicksAdd(DestSymbol, tickArr);
      if(added <= 0)
         PrintFormat("[ReplayEngine] CustomTicksAdd falhou no cursor %d (erro=%d)", g_cursor, GetLastError());

      //--- delta para o próximo tick
      long deltaMs = 0;
      if(g_cursor + 1 < g_total)
      {
         long curMs  = (long)g_ticks[g_cursor].time_msc;
         long nextMs = (long)g_ticks[g_cursor + 1].time_msc;
         deltaMs = nextMs - curMs;
         if(deltaMs < 0) deltaMs = 0;
      }

      g_cursor++;

      if(g_skipToBarEnd && g_cursor < g_total && g_ticks[g_cursor].time >= g_skipTargetTime)
      {
         g_skipToBarEnd = false;
         g_speed        = g_savedSpeed;
         PrintFormat("[ReplayEngine] SKIP_TO_BAR_END concluído — velocidade restaurada para %d", g_speed);
      }

      if(g_cursor % 500 == 0)
         WriteStatus(StringFormat("PLAYING speed=%d cursor=%d/%d", g_speed, g_cursor, g_total));

      if(g_speed < 999)
      {
         long sleepMs = deltaMs / MathMax(g_speed, 1);
         if(sleepMs > 0)
            Sleep((uint)MathMin(sleepMs, 1000));
      }
   }
}

//+------------------------------------------------------------------+
//| Lê e processa comandos de Files\\replay_cmd.txt                  |
//+------------------------------------------------------------------+
void ProcessCommandFile()
{
   if(!FileIsExist(CMD_FILE))
      return;

   int h = FileOpen(CMD_FILE, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   string cmd = "";
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      if(StringLen(line) > 0) { cmd = line; break; }
   }
   FileClose(h);
   FileDelete(CMD_FILE);

   StringToUpper(cmd);
   StringTrimLeft(cmd);
   StringTrimRight(cmd);

   if(cmd == "")              return;
   if(cmd == "PLAY")          { g_paused = false; PrintFormat("[ReplayEngine] CMD PLAY"); return; }
   if(cmd == "PAUSE")         { g_paused = true; g_skipToBarEnd = false; PrintFormat("[ReplayEngine] CMD PAUSE"); return; }
   if(cmd == "STOP")          { g_stopped = true; PrintFormat("[ReplayEngine] CMD STOP"); return; }
   if(cmd == "SKIP")          { g_speed = 999; g_paused = false; g_skipToBarEnd = false; Print("[ReplayEngine] CMD SKIP — avançando até o final em velocidade máxima"); return; }

   if(cmd == "SKIP_TO_BAR_END")
   {
      if(g_cursor < g_total)
      {
         datetime curT     = g_ticks[g_cursor].time;
         datetime barClose = (datetime)((long)curT / 900 * 900) + 900;
         datetime target   = barClose - 5;
         if(target > curT)
         {
            g_savedSpeed     = g_speed;
            g_skipTargetTime = target;
            g_skipToBarEnd   = true;
            g_speed          = 999;
            g_paused         = false;
            PrintFormat("[ReplayEngine] CMD SKIP_TO_BAR_END — alvo %s (faltam %ds para o close)",
                        TimeToString(target, TIME_SECONDS), (int)(barClose - curT));
         }
         else
            Print("[ReplayEngine] SKIP_TO_BAR_END ignorado — já dentro dos 5s finais da barra");
      }
      return;
   }

   if(StringFind(cmd, "SPEED:") == 0)
   {
      string val = StringSubstr(cmd, 6);
      int s = (int)StringToInteger(val);
      if(s == 1 || s == 2 || s == 4 || s == 8 || s == 16 || s == 32)
      {
         g_speed = s;
         g_skipToBarEnd = false;
         PrintFormat("[ReplayEngine] CMD SPEED=%d", g_speed);
      }
      else
         PrintFormat("[ReplayEngine] SPEED inválido: %s", val);
      return;
   }

   PrintFormat("[ReplayEngine] Comando desconhecido: %s", cmd);
}

//+------------------------------------------------------------------+
//| Calcula ATR(period) no AtrTimeframe e exporta para arquivo       |
//+------------------------------------------------------------------+
void ComputeAndExportAtr()
{
   int handle = iATR(SourceSymbol, AtrTimeframe, AtrPeriod);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("[ReplayEngine] iATR falhou (erro=%d)", GetLastError());
      return;
   }

   //--- aguardar o indicador calcular
   for(int i=0; i<50; i++)
   {
      if(BarsCalculated(handle) > AtrPeriod) break;
      Sleep(50);
   }

   double buf[];
   ArraySetAsSeries(buf, true);
   int copied = CopyBuffer(handle, 0, 0, AtrPeriod + 2, buf);
   IndicatorRelease(handle);

   if(copied <= 0)
   {
      PrintFormat("[ReplayEngine] CopyBuffer ATR falhou (copied=%d)", copied);
      return;
   }

   double atr = buf[1]; // último fechado
   int h = FileOpen(ATR_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("[ReplayEngine] Falha ao escrever %s (erro=%d)", ATR_FILE, GetLastError());
      return;
   }
   FileWriteString(h, DoubleToString(atr, Digits_));
   FileClose(h);
   PrintFormat("[ReplayEngine] ATR(%d) %s = %.5f exportado para %s", AtrPeriod, EnumToString(AtrTimeframe), atr, ATR_FILE);
}

//+------------------------------------------------------------------+
//| Escreve status corrente em arquivo                               |
//+------------------------------------------------------------------+
void WriteStatus(const string s)
{
   int h = FileOpen(STATUS_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, s);
   FileClose(h);
}
//+------------------------------------------------------------------+
