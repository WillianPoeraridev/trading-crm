import Link from 'next/link'
import { prisma } from '@/lib/prisma'
import { buttonVariants } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import { format } from 'date-fns'
import { Prisma } from '@prisma/client'

export const dynamic = 'force-dynamic'

type Trade = Prisma.TradeGetPayload<{ include: { pattern: true } }>

function groupBySessionDate(trades: Trade[]) {
  const map = new Map<string, { label: string; ts: number; trades: Trade[] }>()
  for (const t of trades) {
    const key = t.sessionDate
      ? format(new Date(t.sessionDate), 'yyyy-MM-dd')
      : 'no-date'
    if (!map.has(key)) {
      map.set(key, {
        label: t.sessionDate ? format(new Date(t.sessionDate), 'dd/MM/yyyy') : 'Sem data de sessão',
        ts: t.sessionDate ? new Date(t.sessionDate).getTime() : 0,
        trades: [],
      })
    }
    map.get(key)!.trades.push(t)
  }
  return [...map.values()].sort((a, b) => b.ts - a.ts)
}

function slPts(t: Trade) {
  const pts = t.direction === 'LONG'
    ? t.entryPrice - t.stopPrice
    : t.stopPrice - t.entryPrice
  return pts.toFixed(0)
}

function SourceBadge({ source }: { source: string }) {
  return (
    <Badge
      className={cn(
        source === 'REAL'
          ? 'bg-green-500/10 text-green-700 dark:text-green-400'
          : 'bg-blue-500/10 text-blue-700 dark:text-blue-400',
      )}
      variant="outline"
    >
      {source}
    </Badge>
  )
}

function TradeRow({ trade }: { trade: Trade }) {
  return (
    <tr key={trade.id} className="border-t hover:bg-muted/30">
      <td className="px-4 py-2">
        <div className="flex items-center gap-2">
          {trade.screenshotUrl && (
            <img
              src={trade.screenshotUrl}
              alt=""
              className="w-10 h-10 object-cover rounded shrink-0"
            />
          )}
          <Link href={`/trades/${trade.id}`} className="hover:underline whitespace-nowrap">
            {format(new Date(trade.entryTime), 'dd/MM/yyyy HH:mm')}
          </Link>
        </div>
      </td>
      <td className="px-4 py-2">{trade.instrument}</td>
      <td className="px-4 py-2">
        <Badge variant={trade.direction === 'LONG' ? 'default' : 'secondary'}>
          {trade.direction}
        </Badge>
      </td>
      <td className="px-4 py-2">
        <SourceBadge source={trade.source} />
      </td>
      <td className="px-4 py-2 text-right tabular-nums">{slPts(trade)}</td>
      <td className="px-4 py-2 text-right tabular-nums">{trade.rrAchieved.toFixed(2)}R</td>
      <td className="px-4 py-2 text-right tabular-nums">
        {trade.pnlNet != null ? `$${trade.pnlNet.toFixed(2)}` : '—'}
      </td>
      <td className="px-4 py-2">
        <Badge
          variant={
            trade.result === 'WIN'
              ? 'default'
              : trade.result === 'LOSS'
              ? 'destructive'
              : 'secondary'
          }
        >
          {trade.result}
        </Badge>
      </td>
    </tr>
  )
}

function TradeTable({ trades }: { trades: Trade[] }) {
  return (
    <div className="border rounded-lg overflow-hidden">
      <table className="w-full text-sm">
        <thead className="bg-muted/50">
          <tr>
            <th className="text-left px-4 py-3">Data</th>
            <th className="text-left px-4 py-3">Instrumento</th>
            <th className="text-left px-4 py-3">Direção</th>
            <th className="text-left px-4 py-3">Source</th>
            <th className="text-right px-4 py-3">SL pts</th>
            <th className="text-right px-4 py-3">R Obtido</th>
            <th className="text-right px-4 py-3">USD</th>
            <th className="text-left px-4 py-3">Resultado</th>
          </tr>
        </thead>
        <tbody>
          {trades.map((t) => (
            <TradeRow key={t.id} trade={t} />
          ))}
        </tbody>
      </table>
    </div>
  )
}

export default async function TradesPage({
  searchParams,
}: {
  searchParams: Promise<{ source?: string }>
}) {
  const { source } = await searchParams

  const where: Prisma.TradeWhereInput =
    source === 'SIMULATOR' ? { source: 'SIMULATOR' }
    : source === 'REAL'      ? { source: 'REAL' }
    : {}

  const trades = await prisma.trade.findMany({
    where,
    include: { pattern: true },
    orderBy: { entryTime: 'desc' },
  })

  const tabs = [
    { label: 'Simulador', value: 'SIMULATOR' as const },
    { label: 'Real', value: 'REAL' as const },
    { label: 'Visão Geral', value: undefined },
  ]

  return (
    <div className="max-w-6xl mx-auto space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Trades</h1>
        <div className="flex gap-2">
          <Link href="/trades/metrics" className={buttonVariants({ variant: 'outline' })}>
            Métricas
          </Link>
          <Link href="/trades/import-csv" className={buttonVariants({ variant: 'outline' })}>
            Importar CSV
          </Link>
          <Link href="/trades/new" className={buttonVariants()}>
            Novo Trade
          </Link>
        </div>
      </div>

      {/* Tabs by source */}
      <div role="tablist" className="flex border-b">
        {tabs.map(({ label, value }) => {
          const href = value ? `/trades?source=${value}` : '/trades'
          const active = source === value || (!source && !value)
          return (
            <Link
              key={label}
              href={href}
              role="tab"
              aria-selected={active}
              className={cn(
                'px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors',
                active
                  ? 'border-primary text-foreground'
                  : 'border-transparent text-muted-foreground hover:text-foreground',
              )}
            >
              {label}
            </Link>
          )
        })}
      </div>

      {trades.length === 0 ? (
        <p className="text-muted-foreground text-center py-16">
          Nenhum trade registrado ainda.{' '}
          <Link href="/trades/new" className="underline">
            Registrar o primeiro
          </Link>
          .
        </p>
      ) : source === 'SIMULATOR' ? (
        /* grouped view */
        <div className="space-y-6">
          {groupBySessionDate(trades).map(({ label, trades: group }) => (
            <div key={label}>
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2 px-1">
                {label}
              </p>
              <TradeTable trades={group} />
            </div>
          ))}
        </div>
      ) : (
        <TradeTable trades={trades} />
      )}
    </div>
  )
}
