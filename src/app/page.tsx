import Link from 'next/link'
import { prisma } from '@/lib/prisma'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { buttonVariants } from '@/components/ui/button'
import { TrendChart } from '@/components/dashboard/trend-chart'
import { MonteCarloCard } from '@/components/dashboard/monte-carlo-card'
import {
  monthRange,
  previousMonthRange,
  sumR,
  winRateOf,
  mfeVsAchieved,
  avgR,
} from '@/lib/metrics'
import { format } from 'date-fns'
import { cn } from '@/lib/utils'

export const dynamic = 'force-dynamic'

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ view?: string }>
}) {
  const { view } = await searchParams
  const viewSource: 'SIMULATOR' | 'REAL' = view === 'REAL' ? 'REAL' : 'SIMULATOR'

  const now = new Date()
  const { start: monthStart, end: monthEnd } = monthRange(now)
  const { start: prevStart, end: prevEnd } = previousMonthRange(now)

  const sourceFilter = { source: viewSource }

  const [allTrades, currentMonthTrades, previousMonthTrades, last20, totalCount] = await Promise.all([
    prisma.trade.findMany({ where: sourceFilter, orderBy: { entryTime: 'desc' } }),
    prisma.trade.findMany({
      where: { ...sourceFilter, entryTime: { gte: monthStart, lt: monthEnd } },
    }),
    prisma.trade.findMany({
      where: { ...sourceFilter, entryTime: { gte: prevStart, lt: prevEnd } },
    }),
    prisma.trade.findMany({ where: sourceFilter, orderBy: { entryTime: 'desc' }, take: 20 }),
    prisma.trade.count({ where: sourceFilter }),
  ])

  const monthR = sumR(currentMonthTrades)
  const prevMonthR = sumR(previousMonthTrades)
  const monthDelta = monthR - prevMonthR

  const last10 = allTrades.slice(0, 10)
  const prev10 = allTrades.slice(10, 20)
  const wrLast10 = winRateOf(last10)
  const wrPrev10 = winRateOf(prev10)

  const mfe = mfeVsAchieved(allTrades)

  const trendData = [...last20]
    .reverse()
    .map((t, idx) => ({
      idx,
      r: Number(t.rrAchieved.toFixed(2)),
      date: format(new Date(t.entryTime), 'dd/MM HH:mm'),
    }))

  const overallWinRate = winRateOf(allTrades).rate
  const overallAvgR = avgR(allTrades)

  return (
    <div className="max-w-6xl mx-auto space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Dashboard</h1>
        <div className="flex gap-2">
          <Link
            href="/?view=SIMULATOR"
            className={cn(buttonVariants({ variant: viewSource === 'SIMULATOR' ? 'default' : 'outline', size: 'sm' }))}
          >
            Simulador
          </Link>
          <Link
            href="/?view=REAL"
            className={cn(buttonVariants({ variant: viewSource === 'REAL' ? 'default' : 'outline', size: 'sm' }))}
          >
            Real
          </Link>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>R acumulado do mês</CardTitle>
            <CardDescription>
              {format(monthStart, 'MMM/yyyy')} · {currentMonthTrades.length} trades
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex items-baseline gap-3">
              <span
                className={`text-5xl font-bold tabular-nums ${
                  monthR > 0
                    ? 'text-green-600 dark:text-green-400'
                    : monthR < 0
                      ? 'text-red-600 dark:text-red-400'
                      : ''
                }`}
              >
                {monthR > 0 ? '+' : ''}
                {monthR.toFixed(2)}R
              </span>
              <span
                className={`text-base font-medium tabular-nums inline-flex items-center gap-1 ${
                  monthDelta >= 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'
                }`}
                title="vs mês anterior"
              >
                {monthDelta >= 0 ? '▲' : '▼'} {Math.abs(monthDelta).toFixed(2)}R
              </span>
              <span className="text-xs text-muted-foreground">
                vs mês anterior ({prevMonthR.toFixed(2)}R)
              </span>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Win rate (últimas 10)</CardTitle>
            <CardDescription>
              vs anteriores (11–20)
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex items-baseline gap-3">
              <span className="text-3xl font-bold tabular-nums">
                {wrLast10.rate != null ? `${(wrLast10.rate * 100).toFixed(0)}%` : '—'}
              </span>
              <span className="text-sm text-muted-foreground tabular-nums">
                anteriores: {wrPrev10.rate != null ? `${(wrPrev10.rate * 100).toFixed(0)}%` : '—'}
              </span>
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              {wrLast10.wins}/{wrLast10.count} wins · breakeven não conta
            </p>
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Tendência (últimos 20 trades)</CardTitle>
            <CardDescription>R obtido em ordem cronológica</CardDescription>
          </CardHeader>
          <CardContent>
            <TrendChart data={trendData} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Dinheiro deixado na mesa</CardTitle>
            <CardDescription>MFE médio vs R obtido médio</CardDescription>
          </CardHeader>
          <CardContent>
            {mfe.sample === 0 ? (
              <p className="text-sm text-muted-foreground">
                Sem trades com MFE registrado.
              </p>
            ) : (
              <>
                <p className="text-sm">
                  Você saiu em média em{' '}
                  <strong className="tabular-nums">{mfe.avgAchievedR!.toFixed(2)}R</strong>, mas o
                  mercado foi até{' '}
                  <strong className="tabular-nums text-green-700 dark:text-green-400">
                    {mfe.avgMfeR!.toFixed(2)}R
                  </strong>
                  .
                </p>
                <p className="text-xs text-muted-foreground mt-2">
                  Diferença: {(mfe.avgMfeR! - mfe.avgAchievedR!).toFixed(2)}R · amostra de{' '}
                  {mfe.sample} trades
                </p>
              </>
            )}
          </CardContent>
        </Card>
      </div>

      <MonteCarloCard
        totalTrades={totalCount}
        autoWinRate={overallWinRate}
        autoAvgRR={overallAvgR}
      />
    </div>
  )
}
