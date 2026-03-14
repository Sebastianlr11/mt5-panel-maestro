//+------------------------------------------------------------------+
//|                                       Portfolio_Manager_Pro.mq5  |
//|              Task 3: Kill Confirmation + Close Positions + Chart  |
//+------------------------------------------------------------------+
#property copyright "Portfolio Manager Pro"
#property version   "1.00"
#property strict

// ══════════════════════════════════════════════════════════════════
//  CONSTANTS
// ══════════════════════════════════════════════════════════════════
#define PREFIX        "PMP_"
#define TIMER_MS      200          // UI poll interval (ms)
#define SCAN_TICKS    10           // bot scan = 10 × 200ms = 2 s

//--- Layout
#define HDR_H         48
#define SEARCH_Y      56
#define SEARCH_H      32
#define COLHDR_Y      96
#define COLHDR_H      26
#define TABLE_Y       124
#define ROW_H         36
#define SB_W          24           // scrollbar total width (px) — thick
#define SB_BTN_H      24           // arrow button height
#define SB_THUMB_PAD  3            // inset of thumb inside track
#define SB_GRIP_LINES 3            // grip dots count
#define COL_MAGIC_W   148
#define COL_KILL_W    66
#define COL_GAP       10
#define PAD           16
#define MAX_ROWS      30

//--- Confirm modal dimensions
#define MOD_W         600          // dialog width  (px)
#define MOD_H         196          // dialog height (px)

//--- Colors (main panel)
#define CLR_BG          C'3,7,18'
#define CLR_SURFACE     C'15,23,42'
#define CLR_SURFACE2    C'22,33,56'
#define CLR_BORDER      C'51,65,85'
#define CLR_ACCENT      C'129,140,248'
#define CLR_TEXT        C'226,232,240'
#define CLR_MUTED       C'100,116,139'
#define CLR_DIM         C'51,65,85'
#define CLR_ROW_ODD     C'6,11,24'
#define CLR_ROW_EVEN    C'10,18,36'
#define CLR_MAGIC       C'52,211,153'
#define CLR_KILL_BG     C'127,29,29'
#define CLR_KILL_TXT    C'252,165,165'
#define CLR_SB_OUTER    C'10,16,32'
#define CLR_SB_TRACK    C'8,12,24'
#define CLR_SB_THUMB    C'71,85,105'
#define CLR_SB_THUMB_BD C'100,116,139'
#define CLR_SB_GRIP     C'129,140,248'
#define CLR_SB_BTN      C'22,33,56'
#define CLR_SB_BTN_TXT  C'129,140,248'

//--- Colors (modal)
#define CLR_DANGER_BG   C'127,29,29'    // confirm button red bg
#define CLR_DANGER_TXT  C'252,165,165'  // confirm button red text
#define CLR_CANCEL_BG   C'22,33,56'     // cancel button bg
#define CLR_CANCEL_TXT  C'100,116,139'  // cancel button text
#define CLR_MOD_STRIP   C'153,27,27'    // top accent strip on dialog

#define PLACEHOLDER   "  Buscar por nombre o Magic Number..."

// ══════════════════════════════════════════════════════════════════
//  STRUCT
// ══════════════════════════════════════════════════════════════════
struct BotData
{
   long   chartID;
   long   magic;
   string botName;
};

// ══════════════════════════════════════════════════════════════════
//  CManager  —  data layer (scan + filter)
// ══════════════════════════════════════════════════════════════════
class CManager
{
   BotData m_bots[];
private:
   int     m_count;
   int     m_lastTotal;
   int     m_filtered[];
   int     m_filteredCount;

public:
   long ParseMagic(long cid)
   {
      string tplBase = "pmp_tmp_" + IntegerToString(cid);
      string tplFile = tplBase + ".tpl";          // sin path
      string filePath = "\\Files\\" + tplBase;    // path especial para guardar en Files\

      Print("[DEBUG] Intentando guardar plantilla en MQL5\\Files\\ para ChartID: ", cid);

      if(!ChartSaveTemplate(cid, filePath))
      {
         Print("[DEBUG] Fallo en ChartSaveTemplate a Files\\. Error: ", GetLastError());
         // Fallback: intenta guardar sin path (va a Profiles\Templates\)
         if(!ChartSaveTemplate(cid, tplBase))
         {
            Print("[DEBUG] Fallo total en ChartSaveTemplate. No se puede continuar.");
            return 0;
         }
         Print("[DEBUG] Guardado fallback en Profiles\\Templates\\ (lectura puede fallar)");
         filePath = tplFile;  // intentaremos leer directo, pero probablemente fallará
      }
      else
      {
         Print("[DEBUG] Plantilla guardada exitosamente en MQL5\\Files\\");
      }

      // Ahora intentamos leer desde Files\ (más confiable)
      string paths[] = {
         tplFile,                             // directo en Files\
         "\\Files\\" + tplFile,               // con path explícito
         tplBase + ".tpl"                     // sin .tpl extra
      };

      int handle = INVALID_HANDLE;
      for(int i = 0; i < ArraySize(paths); i++)
      {
         Print("[DEBUG] Intentando abrir desde Files/: ", paths[i]);
         handle = FileOpen(paths[i], FILE_READ | FILE_TXT | FILE_UNICODE);
         if(handle != INVALID_HANDLE)
         {
            Print("[DEBUG] ¡Éxito! Archivo abierto (UNICODE) en Files/: ", paths[i]);
            break;
         }
         handle = FileOpen(paths[i], FILE_READ | FILE_TXT | FILE_ANSI);
         if(handle != INVALID_HANDLE)
         {
            Print("[DEBUG] ¡Éxito! Archivo abierto (ANSI) en Files/: ", paths[i]);
            break;
         }
         Print("[DEBUG] Fallo al abrir ", paths[i], " → Error: ", GetLastError());
      }

      if(handle == INVALID_HANDLE)
      {
         Print("[DEBUG] No se pudo abrir el .tpl. Verifica manualmente en carpeta MQL5\\Files\\ si existe ", tplFile);
         Print("[DEBUG] Posibles causas: sandbox MT5, antivirus bloqueando, o ChartSaveTemplate no creó el archivo.");
         return 0;
      }

      // ── Parseo ──────────────────────────────────────────────────────
      long magic     = 0;
      bool inExpert  = false;
      bool inInputs  = false;
      int lineCount  = 0;

      while(!FileIsEnding(handle))
      {
         string line = FileReadString(handle);
         lineCount++;
         StringTrimLeft(line);
         StringTrimRight(line);
         // Print("[DEBUG] Línea ", lineCount, ": ", line);  // Comenta si logs son muy largos

         if(line == "<expert>")    { inExpert  = true;  continue; }
         if(line == "</expert>")   { inExpert  = false; continue; }
         if(inExpert && line == "<inputs>")  { inInputs = true;  continue; }
         if(inExpert && line == "</inputs>") { inInputs = false; break;    }

         if(inExpert && inInputs)
         {
            string keys[] = {"MagicNumber=", "Magic=", "magic_number=", "MagicNum=", "MAGIC=",
                             "ea_magic=", "MN=", "magicNo=", "Identifier="}; 
            for(int k = 0; k < ArraySize(keys); k++)
            {
               if(StringFind(line, keys[k]) == 0)
               {
                  string val = StringSubstr(line, StringLen(keys[k]));
                  string num = "";
                  for(int c = 0; c < StringLen(val); c++)
                  {
                     ushort ch = StringGetCharacter(val, c);
                     if(ch >= '0' && ch <= '9') num += CharToString((uchar)ch);
                     else break;
                  }
                  if(StringLen(num) > 0)
                  {
                     magic = StringToInteger(num);
                     Print("[DEBUG] Magic detectado: ", magic, " en línea: ", line);
                  }
                  break;
               }
            }
            if(magic != 0) break;
         }
      }

      FileClose(handle);

      // Cleanup
      FileDelete(tplFile);
      FileDelete("\\Files\\" + tplFile);

      Print("[DEBUG] Magic final detectado: ", magic);
      return magic;
   }


   CManager() : m_count(0), m_lastTotal(-1), m_filteredCount(0) {}

   int  Count()         const { return m_count; }
   int  FilteredCount() const { return m_filteredCount; }

   // Force the next Scan() to run unconditionally
   void ResetScan()           { m_lastTotal = -1; }

   bool GetFiltered(int i, BotData &out) const
   {
      if(i < 0 || i >= m_filteredCount) return false;
      out = m_bots[m_filtered[i]];
      return true;
   }

   bool Scan()
   {
      int n = 0;
      long id = ChartFirst();
      while(id >= 0) { n++; id = ChartNext(id); }
      // Always scan every cycle (approx 2s) to detect parameter/magic changes live
      m_lastTotal = n;

      ArrayResize(m_bots, n);
      m_count = 0;
      id = ChartFirst();
      while(id >= 0)
      {
         string name = ChartGetString(id, CHART_EXPERT_NAME);
         if(name != "")
         {
            m_bots[m_count].chartID = id;
            m_bots[m_count].magic   = ParseMagic(id);
            m_bots[m_count].botName = name;
            m_count++;
         }
         id = ChartNext(id);
      }
      ArrayResize(m_bots, m_count);
      return true;
   }

   void ApplyFilter(const string &filter)
   {
      ArrayResize(m_filtered, m_count);
      m_filteredCount = 0;
      if(filter == "")
      {
         for(int i = 0; i < m_count; i++) m_filtered[m_filteredCount++] = i;
      }
      else
      {
         string fl = filter; StringToLower(fl);
         for(int i = 0; i < m_count; i++)
         {
            string nl = m_bots[i].botName; StringToLower(nl);
            string ms = IntegerToString(m_bots[i].magic);
            if(StringFind(nl, fl) >= 0 || StringFind(ms, fl) >= 0)
               m_filtered[m_filteredCount++] = i;
         }
      }
      ArrayResize(m_filtered, m_filteredCount);
   }
};

// ══════════════════════════════════════════════════════════════════
//  GLOBALS
// ══════════════════════════════════════════════════════════════════
CManager g_mgr;
int      g_scroll    = 0;
string   g_filter    = "";
int      g_tick      = 0;
bool     g_poolReady = false;

//--- Scrollbar drag state
bool g_sbDrag    = false;
int  g_sbDragY0  = 0;
int  g_sbDragSc0 = 0;

//--- Confirmation modal state
bool   g_confirmOpen    = false;
long   g_confirmChartID = 0;
long   g_confirmMagic   = 0;
string g_confirmName    = "";

// ══════════════════════════════════════════════════════════════════
//  LAYOUT HELPERS  (resize-aware)
// ══════════════════════════════════════════════════════════════════
int CW() { return (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);  }
int CH() { return (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS); }

int VisRows()    { return MathMin(MAX_ROWS, MathMax(0, (CH() - TABLE_Y - PAD) / ROW_H)); }
int ColMagX()    { return PAD; }
int ColNamX()    { return PAD + COL_MAGIC_W + COL_GAP; }
int ColKilX()    { return CW() - PAD - SB_W - COL_GAP - COL_KILL_W; }
int SbX()        { return CW() - PAD - SB_W; }

int SbFullY1()   { return TABLE_Y; }
int SbFullY2()   { return CH() - PAD; }
int SbFullH()    { return MathMax(1, SbFullY2() - SbFullY1()); }
int SbTrackY1()  { return SbFullY1() + SB_BTN_H + 1; }
int SbTrackY2()  { return SbFullY2() - SB_BTN_H - 1; }
int SbTrackH()   { return MathMax(1, SbTrackY2() - SbTrackY1()); }

void ClampScroll()
{
   int maxOff = MathMax(0, g_mgr.FilteredCount() - VisRows());
   g_scroll   = MathMin(MathMax(0, g_scroll), maxOff);
}

// ══════════════════════════════════════════════════════════════════
//  OBJECT PRIMITIVES
// ══════════════════════════════════════════════════════════════════
void SetRect(const string n, int x, int y, int w, int h,
             color bg, int z = 1, color border = clrNONE)
{
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,      MathMax(1, w));
   ObjectSetInteger(0, n, OBJPROP_YSIZE,      MathMax(1, h));
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR,      (border == clrNONE) ? bg : border);
   ObjectSetInteger(0, n, OBJPROP_BACK,       false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,     z);
}

void MoveRect(const string n, int x, int y, int w, int h)
{
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,     MathMax(1, w));
   ObjectSetInteger(0, n, OBJPROP_YSIZE,     MathMax(1, h));
}

void SetLbl(const string n, int x, int y, const string txt, color clr,
            int fs = 9, const string fnt = "Arial",
            ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER, int z = 2)
{
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  fs);
   ObjectSetString (0, n, OBJPROP_FONT,      fnt);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,    z);
}

void MoveLbl(const string n, int x, int y, const string txt, color clr = clrNONE)
{
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, n, OBJPROP_TEXT,      txt);
   if(clr != clrNONE) ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
}

void SetBtn(const string n, int x, int y, int w, int h,
            const string txt, color bg, color fg, int fs = 8, int z = 4)
{
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,      MathMax(1, w));
   ObjectSetInteger(0, n, OBJPROP_YSIZE,      MathMax(1, h));
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,      fg);
   ObjectSetString (0, n, OBJPROP_FONT,       "Arial Bold");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   fs);
   ObjectSetString (0, n, OBJPROP_TEXT,       txt);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_STATE,      false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,     z);
}

// ══════════════════════════════════════════════════════════════════
//  SCROLLBAR — GEOMETRY HELPERS
// ══════════════════════════════════════════════════════════════════
void SbThumbGeometry(int &thumbY, int &thumbH)
{
   int total    = g_mgr.FilteredCount();
   int vis      = VisRows();
   int trackH   = SbTrackH();

   if(total <= vis || total == 0)
   {
      thumbY = SbTrackY1();
      thumbH = trackH;
      return;
   }
   thumbH = MathMax(28, (int)((double)vis / total * trackH));
   int maxOff = total - vis;
   thumbY = SbTrackY1() + (int)((double)g_scroll / maxOff * (trackH - thumbH));
}

bool IsOnThumb(int my)
{
   int ty, th;
   SbThumbGeometry(ty, th);
   return (my >= ty && my <= ty + th);
}

bool IsAboveThumb(int my)
{
   int ty, th;
   SbThumbGeometry(ty, th);
   return (my >= SbTrackY1() && my < ty);
}

bool IsBelowThumb(int my)
{
   int ty, th;
   SbThumbGeometry(ty, th);
   return (my > ty + th && my <= SbTrackY2());
}

// ══════════════════════════════════════════════════════════════════
//  SCROLLBAR — UPDATE
// ══════════════════════════════════════════════════════════════════
void UpdateScrollbar()
{
   int sbx  = SbX();
   int fy1  = SbFullY1();
   int fh   = SbFullH();
   int ty1  = SbTrackY1();
   int th   = SbTrackH();

   MoveRect(PREFIX+"SB_BG", sbx, fy1, SB_W, fh);
   MoveRect(PREFIX+"SB_TR", sbx, ty1, SB_W, th);

   ObjectSetInteger(0, PREFIX+"SB_UP", OBJPROP_XDISTANCE, sbx);
   ObjectSetInteger(0, PREFIX+"SB_UP", OBJPROP_YDISTANCE, fy1);
   ObjectSetInteger(0, PREFIX+"SB_UP", OBJPROP_XSIZE,     SB_W);

   ObjectSetInteger(0, PREFIX+"SB_DN", OBJPROP_XDISTANCE, sbx);
   ObjectSetInteger(0, PREFIX+"SB_DN", OBJPROP_YDISTANCE, SbFullY2() - SB_BTN_H);
   ObjectSetInteger(0, PREFIX+"SB_DN", OBJPROP_XSIZE,     SB_W);

   int thumbY, thumbH;
   SbThumbGeometry(thumbY, thumbH);

   int innerX = sbx + SB_THUMB_PAD;
   int innerW = SB_W - SB_THUMB_PAD * 2;

   MoveRect(PREFIX+"SB_TH",  innerX, thumbY,          innerW, thumbH);
   MoveRect(PREFIX+"SB_THI", innerX, thumbY,           innerW, 1);
   MoveRect(PREFIX+"SB_THB", innerX, thumbY+thumbH-1, innerW, 1);

   int gripMid = thumbY + thumbH / 2;
   int gStart  = gripMid - ((SB_GRIP_LINES - 1) * 4) / 2;
   for(int g = 0; g < SB_GRIP_LINES; g++)
   {
      string gn = PREFIX + "SB_G" + IntegerToString(g);
      int gy    = gStart + g * 4;
      MoveRect(gn, innerX + 3, gy, innerW - 6, 1);
      ObjectSetInteger(0, gn, OBJPROP_BGCOLOR,
                       (thumbH >= 36) ? CLR_SB_GRIP : CLR_SB_THUMB);
   }
}

// ══════════════════════════════════════════════════════════════════
//  CONFIRM MODAL — show / hide
// ══════════════════════════════════════════════════════════════════

// Object name list — kept in sync between Show and Hide
static const string MOD_OBJS[] = {
   "MOD_OVL","MOD_BOX","MOD_STR",
   "MOD_TTL","MOD_NM", "MOD_MG",
   "MOD_W1", "MOD_W2",
   "MOD_CX", "MOD_OK"
};

void ShowConfirm(long chartID, long magic, const string &name)
{
   g_confirmOpen    = true;
   g_confirmChartID = chartID;
   g_confirmMagic   = magic;
   g_confirmName    = name;

   int W  = CW(), H = CH();
   int bx = (W - MOD_W) / 2;
   int by = (H - MOD_H) / 2;

   // Full-panel dimmer (z=8 — above table, below modal)
   SetRect(PREFIX+"MOD_OVL", 0, 0, W, H, C'3,7,18', 8);

   // Dialog box + top accent strip
   SetRect(PREFIX+"MOD_BOX", bx,    by,  MOD_W,  MOD_H,  CLR_SURFACE, 9, CLR_BORDER);
   SetRect(PREFIX+"MOD_STR", bx,    by,  MOD_W,  4,      CLR_MOD_STRIP, 10);

   // Title
   SetLbl(PREFIX+"MOD_TTL", bx + MOD_W/2, by + 16,
          "CONFIRMAR CIERRE", CLR_KILL_TXT, 10, "Arial Bold",
          ANCHOR_UPPER, 10);

   // Bot name (truncated to fit modal width)
   string botShort = name;
   if(StringLen(botShort) > 80) botShort = StringSubstr(botShort, 0, 77) + "...";
   SetLbl(PREFIX+"MOD_NM", bx + 16, by + 44,
          botShort, CLR_TEXT, 9, "Arial", ANCHOR_LEFT_UPPER, 10);

   // Magic number
   string magStr = (magic == 0) ? "Magic: —" : "Magic:  " + IntegerToString(magic);
   color  magClr = (magic == 0) ? CLR_MUTED : CLR_MAGIC;
   SetLbl(PREFIX+"MOD_MG", bx + 16, by + 64,
          magStr, magClr, 9, "Arial Bold", ANCHOR_LEFT_UPPER, 10);

   // Warning lines
   string w1, w2;
   if(magic == 0)
   {
      w1 = "Sin Magic Number — solo se cerrara el grafico.";
      w2 = "";
   }
   else
   {
      w1 = "Cerrara TODAS las posiciones abiertas con";
      w2 = "este Magic y luego el grafico. Sin deshacer.";
   }
   SetLbl(PREFIX+"MOD_W1", bx + 16, by + 92,
          w1, CLR_MUTED, 8, "Arial", ANCHOR_LEFT_UPPER, 10);
   SetLbl(PREFIX+"MOD_W2", bx + 16, by + 108,
          w2, CLR_MUTED, 8, "Arial", ANCHOR_LEFT_UPPER, 10);

   // Buttons
   int btnY = by + MOD_H - 50;
   int btnW = (MOD_W - 48) / 2;

   SetBtn(PREFIX+"MOD_CX", bx + 16,            btnY, btnW, 34,
          "Cancelar",  CLR_CANCEL_BG,  CLR_CANCEL_TXT,  9, 10);
   SetBtn(PREFIX+"MOD_OK", bx + MOD_W/2 + 8,   btnY, btnW, 34,
          "Cerrar Bot", CLR_DANGER_BG, CLR_DANGER_TXT,  9, 10);

   ChartRedraw(0);
}

void HideConfirm()
{
   g_confirmOpen = false;
   for(int i = 0; i < ArraySize(MOD_OBJS); i++)
      ObjectDelete(0, PREFIX + MOD_OBJS[i]);
   ChartRedraw(0);
}


// ══════════════════════════════════════════════════════════════════
//  KILL BOT — close positions + pending orders (MQL5 style) + chart
// ══════════════════════════════════════════════════════════════════
void KillBot(long chartID, long magic)
{
   if(magic == 0)
   {
      // Solo cerramos el gráfico si no hay magic
      if(!ChartClose(chartID))
         PrintFormat("[KILL] Aviso: ChartClose(%I64d) falló.", chartID);
      g_mgr.ResetScan();
      g_mgr.Scan();
      g_mgr.ApplyFilter(g_filter);
      UpdateCountBadge();
      TableRedraw();
      return;
   }

   int closed_positions = 0;
   int closed_orders    = 0;
   int errors           = 0;

   // 1. Cerrar POSICIONES ABIERTAS
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != magic) continue;

      string sym  = PositionGetString(POSITION_SYMBOL);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action    = TRADE_ACTION_DEAL;
      req.position  = ticket;
      req.symbol    = sym;
      req.volume    = vol;
      req.type      = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price     = (req.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      req.deviation = 20;

      if(OrderSend(req, res))
      {
         closed_positions++;
         PrintFormat("[KILL POS] OK  ticket=#%I64u  %s  vol=%.2f", ticket, sym, vol);
      }
      else
      {
         errors++;
         PrintFormat("[KILL POS] ERR ticket=#%I64u  retcode=%u  %s", ticket, res.retcode, res.comment);
      }
   }

   // 2. Cerrar ÓRDENES PENDIENTES (sintaxis correcta MQL5)
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;

      if(!OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != magic) continue;

      string sym = OrderGetString(ORDER_SYMBOL);
      if(sym == "") continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;

      if(OrderSend(req, res))
      {
         closed_orders++;
         PrintFormat("[KILL PEND] OK  ticket=#%I64u  %s  tipo=%lld", ticket, sym, OrderGetInteger(ORDER_TYPE));
      }
      else
      {
         errors++;
         PrintFormat("[KILL PEND] ERR ticket=#%I64u  retcode=%u  %s", ticket, res.retcode, res.comment);
      }
   }

   PrintFormat("[KILL] Posiciones cerradas: %d | Órdenes pendientes cerradas: %d | Errores: %d | ChartID=%I64d",
               closed_positions, closed_orders, errors, chartID);

   // 3. Cerrar el gráfico
   if(!ChartClose(chartID))
      PrintFormat("[KILL] Aviso: ChartClose(%I64d) falló.", chartID);

   // Refrescar la tabla
   g_mgr.ResetScan();
   g_mgr.Scan();
   g_mgr.ApplyFilter(g_filter);
   UpdateCountBadge();
   TableRedraw();
}

// ══════════════════════════════════════════════════════════════════
//  PANEL — STATIC LAYER  (re-called on resize)
// ══════════════════════════════════════════════════════════════════
void PanelDestroy() { ObjectsDeleteAll(0, PREFIX); g_poolReady = false; }

void PanelDrawStatic()
{
   int W = CW(), H = CH();

   SetRect(PREFIX+"BG",     0, 0, W, H, CLR_BG, 0);
   SetRect(PREFIX+"HDR",    0, 0, W, HDR_H, CLR_SURFACE, 1, CLR_BORDER);
   SetRect(PREFIX+"HDR_LN", 0, HDR_H-1, W, 1, CLR_BORDER, 2);

   SetLbl(PREFIX+"TITLE",   PAD, 14, "Portfolio Manager Pro",
          CLR_ACCENT, 13, "Arial Bold", ANCHOR_LEFT_UPPER, 3);
   SetLbl(PREFIX+"COUNT",   W - PAD - SB_W - COL_GAP, 16, "bots: —",
          CLR_MUTED, 9, "Arial", ANCHOR_RIGHT_UPPER, 3);

   string se = PREFIX+"SRCH";
   if(ObjectFind(0, se) < 0)
   {
      ObjectCreate(0, se, OBJ_EDIT, 0, 0, 0);
      ObjectSetString(0, se, OBJPROP_TEXT, PLACEHOLDER);
      ObjectSetInteger(0, se, OBJPROP_COLOR, CLR_MUTED);
   }
   ObjectSetInteger(0, se, OBJPROP_XDISTANCE,   PAD);
   ObjectSetInteger(0, se, OBJPROP_YDISTANCE,   SEARCH_Y);
   ObjectSetInteger(0, se, OBJPROP_XSIZE,       W - PAD*2 - SB_W - COL_GAP);
   ObjectSetInteger(0, se, OBJPROP_YSIZE,       SEARCH_H);
   ObjectSetInteger(0, se, OBJPROP_BGCOLOR,     CLR_SURFACE2);
   ObjectSetInteger(0, se, OBJPROP_BORDER_COLOR,CLR_BORDER);
   ObjectSetInteger(0, se, OBJPROP_FONTSIZE,    9);
   ObjectSetString (0, se, OBJPROP_FONT,        "Arial");
   ObjectSetInteger(0, se, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, se, OBJPROP_ZORDER,      4);

   SetRect(PREFIX+"CHDR",   0, COLHDR_Y, W - SB_W - PAD, COLHDR_H,
           CLR_SURFACE, 1, CLR_BORDER);
   SetRect(PREFIX+"CHDR_LN",0, COLHDR_Y+COLHDR_H-1, W, 1, CLR_BORDER, 2);
   SetLbl(PREFIX+"CH_MG", ColMagX()+2, COLHDR_Y+7, "MAGIC NUMBER",
          CLR_DIM, 7, "Arial Bold");
   SetLbl(PREFIX+"CH_NM", ColNamX()+2, COLHDR_Y+7, "ARCHIVO .EX5",
          CLR_DIM, 7, "Arial Bold");
   SetLbl(PREFIX+"CH_KI", ColKilX()+8, COLHDR_Y+7, "ACCION",
          CLR_DIM, 7, "Arial Bold");

   // ── SCROLLBAR ────────────────────────────────────────────────
   int sbx = SbX();
   int fy1 = SbFullY1(), fh = SbFullH();
   int ty1 = SbTrackY1(), th = SbTrackH();

   SetRect(PREFIX+"SB_BG", sbx, fy1, SB_W, fh, CLR_SB_OUTER, 1, CLR_BORDER);
   SetBtn(PREFIX+"SB_UP",  sbx, fy1, SB_W, SB_BTN_H, "  ^",
          CLR_SB_BTN, CLR_SB_BTN_TXT, 8, 4);
   SetRect(PREFIX+"SB_TR", sbx, ty1, SB_W, th, CLR_SB_TRACK, 2);

   int innerX = sbx + SB_THUMB_PAD;
   int innerW = SB_W - SB_THUMB_PAD * 2;
   SetRect(PREFIX+"SB_TH",  innerX, ty1, innerW, 40,
           CLR_SB_THUMB, 3, CLR_SB_THUMB_BD);
   SetRect(PREFIX+"SB_THI", innerX, ty1,    innerW, 1, CLR_SB_THUMB_BD, 4);
   SetRect(PREFIX+"SB_THB", innerX, ty1+40, innerW, 1, CLR_SB_OUTER,   4);

   for(int g = 0; g < SB_GRIP_LINES; g++)
      SetRect(PREFIX+"SB_G"+IntegerToString(g),
              innerX+3, ty1+16+g*4, innerW-6, 1, CLR_SB_GRIP, 4);

   SetBtn(PREFIX+"SB_DN", sbx, SbFullY2()-SB_BTN_H, SB_W, SB_BTN_H, "  v",
          CLR_SB_BTN, CLR_SB_BTN_TXT, 8, 4);

   UpdateScrollbar();
}

// ══════════════════════════════════════════════════════════════════
//  ROW POOL — create MAX_ROWS objects once; move on every update
// ══════════════════════════════════════════════════════════════════
void BuildRowPool()
{
   if(g_poolReady) return;
   g_poolReady = true;
   int park = CH() + 400;

   for(int i = 0; i < MAX_ROWS; i++)
   {
      string si = IntegerToString(i);
      SetRect(PREFIX+"R"+si+"_BG",
              0, park, CW()-SB_W-PAD, ROW_H-1,
              (i%2==0) ? CLR_ROW_ODD : CLR_ROW_EVEN, 1);
      SetRect(PREFIX+"R"+si+"_DV",
              0, park+ROW_H-2, CW()-SB_W-PAD, 1, CLR_BORDER, 2);
      SetLbl(PREFIX+"R"+si+"_MG",
             ColMagX(), park, "—", CLR_DIM, 9, "Courier New",
             ANCHOR_LEFT_UPPER, 3);
      SetLbl(PREFIX+"R"+si+"_NM",
             ColNamX(), park, "", CLR_TEXT, 9, "Arial",
             ANCHOR_LEFT_UPPER, 3);

      string kn = PREFIX+"R"+si+"_KI";
      if(ObjectFind(0,kn)<0) ObjectCreate(0,kn,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,kn,OBJPROP_XDISTANCE, ColKilX());
      ObjectSetInteger(0,kn,OBJPROP_YDISTANCE, park);
      ObjectSetInteger(0,kn,OBJPROP_XSIZE,     COL_KILL_W);
      ObjectSetInteger(0,kn,OBJPROP_YSIZE,     ROW_H-10);
      ObjectSetInteger(0,kn,OBJPROP_BGCOLOR,   CLR_KILL_BG);
      ObjectSetInteger(0,kn,OBJPROP_COLOR,     CLR_KILL_TXT);
      ObjectSetString (0,kn,OBJPROP_FONT,      "Arial Bold");
      ObjectSetInteger(0,kn,OBJPROP_FONTSIZE,  8);
      ObjectSetString (0,kn,OBJPROP_TEXT,      "  KILL");
      ObjectSetInteger(0,kn,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,kn,OBJPROP_STATE,     false);
      ObjectSetInteger(0,kn,OBJPROP_ZORDER,    5);
   }
}

// ══════════════════════════════════════════════════════════════════
//  TABLE REDRAW — zero allocations (only property updates)
// ══════════════════════════════════════════════════════════════════
void TableRedraw()
{
   ClampScroll();
   int vis  = VisRows();
   int tot  = g_mgr.FilteredCount();
   int W    = CW(), H = CH();
   int park = H + 400;

   for(int i = 0; i < MAX_ROWS; i++)
   {
      string si   = IntegerToString(i);
      int    di   = g_scroll + i;
      bool   show = (i < vis) && (di < tot);
      int    ry   = show ? (TABLE_Y + i * ROW_H) : park;

      MoveRect(PREFIX+"R"+si+"_BG", 0, ry, W-SB_W-PAD, ROW_H-1);
      ObjectSetInteger(0, PREFIX+"R"+si+"_BG", OBJPROP_BGCOLOR,
                       (i%2==0) ? CLR_ROW_ODD : CLR_ROW_EVEN);
      MoveRect(PREFIX+"R"+si+"_DV", 0, ry+ROW_H-2, W-SB_W-PAD, 1);

      int ty = ry + (ROW_H - 9) / 2;

      if(show)
      {
         BotData b; g_mgr.GetFiltered(di, b);
         string ms = (b.magic == 0) ? "—" : IntegerToString(b.magic);
         MoveLbl(PREFIX+"R"+si+"_MG", ColMagX(), ty, ms,
                 (b.magic==0) ? CLR_DIM : CLR_MAGIC);
         string nm = b.botName;
         if(StringLen(nm) > 80) nm = StringSubstr(nm,0,77)+"...";
         MoveLbl(PREFIX+"R"+si+"_NM", ColNamX(), ty, nm, CLR_TEXT);
         ObjectSetInteger(0,PREFIX+"R"+si+"_KI",OBJPROP_XDISTANCE, ColKilX());
         ObjectSetInteger(0,PREFIX+"R"+si+"_KI",OBJPROP_YDISTANCE, ry+5);
         ObjectSetInteger(0,PREFIX+"R"+si+"_KI",OBJPROP_XSIZE,     COL_KILL_W);
         ObjectSetInteger(0,PREFIX+"R"+si+"_KI",OBJPROP_YSIZE,     ROW_H-10);
      }
      else
      {
         MoveLbl(PREFIX+"R"+si+"_MG", ColMagX(), park, "");
         MoveLbl(PREFIX+"R"+si+"_NM", ColNamX(), park, "");
         ObjectSetInteger(0,PREFIX+"R"+si+"_KI",OBJPROP_YDISTANCE, park);
      }
   }

   UpdateScrollbar();
   ChartRedraw(0);
}

// ══════════════════════════════════════════════════════════════════
//  COUNT BADGE
// ══════════════════════════════════════════════════════════════════
void UpdateCountBadge()
{
   int   tot = g_mgr.Count(), filt = g_mgr.FilteredCount();
   string t  = (g_filter == "")
               ? "bots: "+IntegerToString(tot)
               : IntegerToString(filt)+"/"+IntegerToString(tot)+" encontrados";
   ObjectSetString (0, PREFIX+"COUNT", OBJPROP_TEXT,      t);
   ObjectSetInteger(0, PREFIX+"COUNT", OBJPROP_XDISTANCE, CW()-PAD-SB_W-COL_GAP);
}

// ══════════════════════════════════════════════════════════════════
//  FULL REFRESH  (init + resize)
// ══════════════════════════════════════════════════════════════════
void FullRefresh()
{
   PanelDrawStatic();
   BuildRowPool();
   UpdateCountBadge();
   TableRedraw();
   // Reposition modal if it was open when a chart resize occurred
   if(g_confirmOpen)
      ShowConfirm(g_confirmChartID, g_confirmMagic, g_confirmName);
}

// ══════════════════════════════════════════════════════════════════
//  EA LIFECYCLE
// ══════════════════════════════════════════════════════════════════
int OnInit()
{
   ChartSetInteger(0, CHART_SHOW_GRID,         false);
   ChartSetInteger(0, CHART_SHOW_VOLUMES,       false);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP,    false);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE,      false);
   ChartSetInteger(0, CHART_SHOW_BID_LINE,      false);
   ChartSetInteger(0, CHART_SHOW_OHLC,          false);
   ChartSetInteger(0, CHART_SHOW_ONE_CLICK,     false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND,   CLR_BG);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND,   CLR_BG);
   ChartSetInteger(0, CHART_EVENT_MOUSE_WHEEL,  true);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE,   true);

   PanelDestroy();
   g_mgr.Scan();
   g_mgr.ApplyFilter("");
   FullRefresh();

   EventSetMillisecondTimer(TIMER_MS);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   PanelDestroy();
   ChartSetInteger(0, CHART_SHOW_GRID,        true);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE,    true);
   ChartSetInteger(0, CHART_SHOW_BID_LINE,    true);
   ChartSetInteger(0, CHART_EVENT_MOUSE_WHEEL,false);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'26,26,26');
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, C'200,200,200');
   ChartRedraw(0);
}

//--- 200ms: real-time search poll + 2s bot scan
void OnTimer()
{
   // (A) Real-time search
   string editTxt = ObjectGetString(0, PREFIX+"SRCH", OBJPROP_TEXT);
   if(editTxt == PLACEHOLDER) editTxt = "";
   if(editTxt != g_filter)
   {
      g_filter = editTxt;
      g_scroll = 0;
      g_mgr.ApplyFilter(g_filter);
      UpdateCountBadge();
      TableRedraw();
   }

   // (B) Bot scan every 2 s
   if(++g_tick >= SCAN_TICKS)
   {
      g_tick = 0;
      if(g_mgr.Scan())
      {
         g_mgr.ApplyFilter(g_filter);
         UpdateCountBadge();
         TableRedraw();
      }
   }
}

void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   // ── (1) Mouse MOVE — scrollbar drag ───────────────────────────
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int mx       = (int)lparam;
      int my       = (int)dparam;
      bool lbDown  = ((int)StringToInteger(sparam) & 1) != 0;
      bool onSbX   = (mx >= SbX() && mx <= SbX() + SB_W);

      if(lbDown && onSbX)
      {
         if(!g_sbDrag && IsOnThumb(my))
         {
            g_sbDrag    = true;
            g_sbDragY0  = my;
            g_sbDragSc0 = g_scroll;
         }

         if(g_sbDrag)
         {
            int   trkH   = SbTrackH();
            int   total  = g_mgr.FilteredCount();
            int   vis    = VisRows();
            int   maxOff = MathMax(1, total - vis);
            int   thumbH = MathMax(28, (int)((double)vis / total * trkH));
            int   travel = trkH - thumbH;
            if(travel > 0)
            {
               double ratio = (double)(my - g_sbDragY0) / travel;
               g_scroll = g_sbDragSc0 + (int)(ratio * maxOff);
               ClampScroll();
               TableRedraw();
            }
         }
      }
      else
      {
         g_sbDrag = false;
      }
      return;
   }

   // ── (2) Mouse WHEEL ───────────────────────────────────────────
   if(id == CHARTEVENT_MOUSE_WHEEL)
   {
      g_scroll += (dparam > 0) ? -3 : 3;
      ClampScroll();
      TableRedraw();
      return;
   }

   // ── (3) Object clicks ─────────────────────────────────────────
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      //--- Search box: clear placeholder
      if(sparam == PREFIX+"SRCH")
      {
         if(ObjectGetString(0,PREFIX+"SRCH",OBJPROP_TEXT) == PLACEHOLDER)
         {
            ObjectSetString (0,PREFIX+"SRCH",OBJPROP_TEXT,"");
            ObjectSetInteger(0,PREFIX+"SRCH",OBJPROP_COLOR,CLR_TEXT);
         }
         return;
      }

      //--- Modal: CONFIRM — close positions + chart
      if(sparam == PREFIX+"MOD_OK" && g_confirmOpen)
      {
         long cid = g_confirmChartID;
         long mag = g_confirmMagic;
         HideConfirm();
         KillBot(cid, mag);
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         return;
      }

      //--- Modal: CANCEL
      if(sparam == PREFIX+"MOD_CX" && g_confirmOpen)
      {
         HideConfirm();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         return;
      }

      //--- Scrollbar UP
      if(sparam == PREFIX+"SB_UP")
      {
         g_scroll--;
         ClampScroll();
         TableRedraw();
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         return;
      }

      //--- Scrollbar DOWN
      if(sparam == PREFIX+"SB_DN")
      {
         g_scroll++;
         ClampScroll();
         TableRedraw();
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         return;
      }

      //--- Scrollbar TRACK (page scroll handled via drag)
      if(sparam == PREFIX+"SB_TR") return;

      //--- KILL button — open confirmation modal (ignore if modal already open)
      string pfx = PREFIX+"R";
      if(!g_confirmOpen &&
         StringFind(sparam, pfx) == 0 &&
         StringFind(sparam, "_KI") > 0)
      {
         int p1 = StringLen(pfx);
         int p2 = StringFind(sparam, "_KI");
         int ri = (int)StringToInteger(StringSubstr(sparam, p1, p2-p1));
         int di = g_scroll + ri;
         BotData b;
          if(g_mgr.GetFiltered(di, b))
          {
             // ── Security: re-validate directly from the chart ──
             string liveName = ChartGetString(b.chartID, CHART_EXPERT_NAME);
             if(liveName == "")
             {
                // Chart gone or EA removed — refresh the table
                PrintFormat("[KILL] Chart %I64d no longer valid; refreshing.", b.chartID);
                g_mgr.ResetScan();
                g_mgr.Scan();
                g_mgr.ApplyFilter(g_filter);
                UpdateCountBadge();
                TableRedraw();
             }
             else
             {
                long liveMagic = g_mgr.ParseMagic(b.chartID);
                ShowConfirm(b.chartID, liveMagic, liveName);
             }
          }
          ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         return;
      }
   }

   // ── (4) Chart resize ──────────────────────────────────────────
   if(id == CHARTEVENT_CHART_CHANGE)
      FullRefresh();
}
//+------------------------------------------------------------------+