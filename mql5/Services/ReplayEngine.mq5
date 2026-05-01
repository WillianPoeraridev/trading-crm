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
input datetime SessionDate       = 0;             // data do replay (0 = hoje)
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
input datetime EndDate           = 0;             // data final do replay (0 = fim do dia de SessionDate)
input int      MaxTicksPerDay    = 500000;        // capacidade do buffer de ticks
input int      AtrPeriod         = 10;            // período do ATR
input ENUM_TIMEFRAMES AtrTimeframe = PERIOD_M15;  // timeframe do ATR

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

   g_startTime = ComputeStartTime(SessionDate);
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
//| Carrega ticks do dia a partir do startTime                       |
//+------------------------------------------------------------------+
bool LoadTicks(datetime startTime)
{
   ulong startMs = (ulong)startTime * 1000UL;
   ArrayResize(g_ticks, MaxTicksPerDay);
   ArraySetAsSeries(g_ticks, false);

   ResetLastError();
   int copied = CopyTicks(SourceSymbol, g_ticks, COPY_TICKS_ALL, startMs, MaxTicksPerDay);
   if(copied <= 0)
   {
      PrintFormat("[ReplayEngine] CopyTicks retornou %d (erro=%d)", copied, GetLastError());
      g_total = 0;
      return false;
   }
   g_total = copied;
   ArrayResize(g_ticks, g_total);
   PrintFormat("[ReplayEngine] %d ticks copiados de %s a partir de %s", g_total, SourceSymbol, TimeToString(startTime, TIME_DATE|TIME_SECONDS));

   // Calcular g_endTime e truncar array
   if(EndDate > 0 && EndDate > g_startTime)
      g_endTime = EndDate;
   else
      g_endTime = (datetime)((long)g_startTime / 86400 * 86400 + 86400); // fim do dia de startTime

   int endIdx = g_total;
   for(int i = 0; i < g_total; i++)
   {
      if((datetime)(g_ticks[i].time_msc / 1000) >= g_endTime)
      {
         endIdx = i;
         break;
      }
   }
   g_total = endIdx;
   PrintFormat("[ReplayEngine] Replay limitado a %d ticks até %s", g_total, TimeToString(g_endTime, TIME_DATE|TIME_SECONDS));
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
   if(cmd == "PAUSE")         { g_paused = true;  PrintFormat("[ReplayEngine] CMD PAUSE"); return; }
   if(cmd == "STOP")          { g_stopped = true; PrintFormat("[ReplayEngine] CMD STOP"); return; }
   if(cmd == "SKIP")          { g_speed = 999; g_paused = false; Print("[ReplayEngine] CMD SKIP — avançando até o final em velocidade máxima"); return; }

   if(StringFind(cmd, "SPEED:") == 0)
   {
      string val = StringSubstr(cmd, 6);
      int s = (int)StringToInteger(val);
      if(s == 1 || s == 2 || s == 4 || s == 8 || s == 16 || s == 32)
      {
         g_speed = s;
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
