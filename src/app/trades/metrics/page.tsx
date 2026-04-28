import Link from 'next/link'
import { prisma } from '@/lib/prisma'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { buttonVariants } from '@/components/ui/button'
import {
  winRateOf,
  avgR,
  profitFactor,
  streaks,
  maxDrawdownR,
  rrRetro,
} from '@/lib/metrics'

export const dynamic = 'force-dynamic'

export default async function MetricsPage() {
  const trades = await prisma.trade.findMany({ orderBy: { entryTime: 'asc' } })

  const sim = trades.filter((t) => t.source === 'SIMULATOR')
  const real = trades.filter((t) => t.source === 'REAL')

  const wrAll = winRateOf(trades)
  const wrSim = winRateOf(sim)
  const wrReal = winRateOf(real)

  const avgRAll = avgR(trades)
  const pf = profitFactor(trades)
  const st = streaks(trades)
  const ddR = maxDrawdownR(trades)
  const retro = rrRetro(trades)

  return (
    <div className="max-w-6xl mx-auto space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Métricas</h1>
        <Link href="/trades" className={buttonVariants({ variant: 'outline' })}>
          ← Trades
        </Link>
      </div>

      {trades.length === 0 ? (
        <p className="text-muted-foreground text-center py-16">
          Nenhum trade registrado ainda.
        </p>
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <MetricCard title="Win rate geral" value={fmtPct(wrAll.rate)} sub={`${wrAll.wins}/${wrAll.count}`} />
            <MetricCard
              title="WR Simulador / Real"
              value={`${fmtPct(wrSim.rate)} / ${fmtPct(wrReal.rate)}`}
              sub={`${wrSim.count} sim · ${wrReal.count} real`}
            />
            <MetricCard
              title="R médio por trade"
              value={avgRAll != null ? `${avgRAll.toFixed(2)}R` : '—'}
              sub={`em ${trades.length} trades`}
              accent={avgRAll != null && avgRAll > 0 ? 'text-green-600 dark:text-green-400' : avgRAll != null && avgRAll < 0 ? 'text-red-600 dark:text-red-400' : undefined}
            />
            <MetricCard
              title="Fator de lucro"
              value={pf == null ? '—' : pf === Infinity ? '∞' : pf.toFixed(2)}
              sub="Σ wins R / Σ |losses| R"
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <MetricCard
              title="Sequência atual"
              value={st.currentType ? `${st.current} ${st.currentType}` : '—'}
              sub="ignora breakeven"
              accent={
                st.currentType === 'WIN'
                  ? 'text-green-600 dark:text-green-400'
                  : st.currentType === 'LOSS'
                    ? 'text-red-600 dark:text-red-400'
                    : undefined
              }
            />
            <MetricCard title="Maior sequência WIN" value={`${st.longestWin}`} sub="histórica" />
            <MetricCard title="Maior sequência LOSS" value={`${st.longestLoss}`} sub="histórica" />
            <MetricCard
              title="Drawdown máximo"
              value={`${ddR.toFixed(2)}R`}
              sub="maior queda desde um pico"
              accent="text-red-600 dark:text-red-400"
            />
          </div>

          <Card>
            <CardHeader>
              <CardTitle>RR retroativo</CardTitle>
              <CardDescription>
                % de trades que atingiram cada nível (entre os que têm dado registrado em hit1R–hit5R)
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
                {retro.map((r) => (
                  <div key={r.level} className="rounded-lg border p-3">
                    <p className="text-[10px] uppercase tracking-wide text-muted-foreground">
                      {r.level}R
                    </p>
                    <p className="text-2xl font-bold tabular-nums">
                      {r.rate != null ? `${(r.rate * 100).toFixed(0)}%` : '—'}
                    </p>
                    <p className="text-[11px] text-muted-foreground tabular-nums">
                      {r.hit}/{r.eligible} trades
                    </p>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}

function fmtPct(v: number | null) {
  return v == null ? '—' : `${(v * 100).toFixed(1)}%`
}

function MetricCard({
  title,
  value,
  sub,
  accent,
}: {
  title: string
  value: string
  sub?: string
  accent?: string
}) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <p className={`text-2xl font-bold tabular-nums ${accent ?? ''}`}>{value}</p>
        {sub && <p className="text-[11px] text-muted-foreground mt-1">{sub}</p>}
      </CardContent>
    </Card>
  )
}
