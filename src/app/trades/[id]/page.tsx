import type React from 'react'
import { notFound } from 'next/navigation'
import Link from 'next/link'
import { prisma } from '@/lib/prisma'
import { Badge } from '@/components/ui/badge'
import { buttonVariants } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { cn } from '@/lib/utils'
import { format } from 'date-fns'

export const dynamic = 'force-dynamic'

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="font-medium text-sm mt-0.5">{value ?? '—'}</dd>
    </div>
  )
}

export default async function TradePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const trade = await prisma.trade.findUnique({
    where: { id },
    include: { pattern: true },
  })

  if (!trade) notFound()

  const slPts =
    trade.direction === 'LONG'
      ? (trade.entryPrice - trade.stopPrice).toFixed(0)
      : (trade.stopPrice - trade.entryPrice).toFixed(0)

  const tpPts =
    trade.direction === 'LONG'
      ? (trade.targetPrice - trade.entryPrice).toFixed(0)
      : (trade.entryPrice - trade.targetPrice).toFixed(0)

  const hitLevels: { label: string; hit: boolean | null }[] = [
    { label: '1R', hit: trade.hit1R },
    { label: '2R', hit: trade.hit2R },
    { label: '3R', hit: trade.hit3R },
    { label: '4R', hit: trade.hit4R },
    { label: '5R', hit: trade.hit5R },
  ]

  return (
    <div className="max-w-2xl mx-auto space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Trade</h1>
        <div className="flex gap-2">
          <Link href={`/trades/${id}/edit`} className={buttonVariants({ variant: 'outline' })}>
            Editar
          </Link>
          <Link href="/trades" className={buttonVariants({ variant: 'ghost' })}>
            Voltar
          </Link>
        </div>
      </div>

      {/* Header card */}
      <Card>
        <CardHeader>
          <CardTitle className="flex flex-wrap items-center gap-2">
            {trade.instrument}
            <Badge variant={trade.direction === 'LONG' ? 'default' : 'secondary'}>
              {trade.direction}
            </Badge>
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
            <Badge
              className={cn(
                trade.source === 'REAL'
                  ? 'bg-green-500/10 text-green-700 dark:text-green-400'
                  : 'bg-blue-500/10 text-blue-700 dark:text-blue-400',
              )}
              variant="outline"
            >
              {trade.source}
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <dl className="grid grid-cols-2 gap-x-6 gap-y-3">
            <Field label="Instrumento" value={trade.instrument} />
            <Field label="Direção" value={trade.direction} />
            <Field
              label="Entrada"
              value={format(new Date(trade.entryTime), 'dd/MM/yyyy HH:mm')}
            />
            <Field
              label="Data da sessão"
              value={
                trade.sessionDate
                  ? format(new Date(trade.sessionDate), 'dd/MM/yyyy')
                  : null
              }
            />
            <Field label="Preço entrada" value={trade.entryPrice} />
            <Field label="Preço saída" value={trade.exitPrice} />
            <Field label="Stop" value={trade.stopPrice} />
            <Field label="Alvo" value={trade.targetPrice} />
            <Field label="SL pts" value={slPts} />
            <Field label="TP pts" value={tpPts} />
            <Field label="Motivo saída" value={trade.exitReason} />
            <Field label="Contratos (lotSize)" value={trade.contractsQty} />
            <Field label="R Planejado" value={`${trade.rrPlanned.toFixed(2)}R`} />
            <Field label="R Obtido" value={`${trade.rrAchieved.toFixed(2)}R`} />
            <Field
              label="R Potencial"
              value={trade.rrPotential != null ? `${trade.rrPotential.toFixed(2)}R` : null}
            />
            <Field
              label="USD (pnlNet)"
              value={trade.pnlNet != null ? `$${trade.pnlNet.toFixed(2)}` : null}
            />
            <Field label="Padrão" value={trade.pattern?.name} />
            <Field label="Comissão" value={trade.commission != null ? `$${trade.commission.toFixed(2)}` : null} />
            <Field label="Duração (min)" value="—" />
          </dl>
        </CardContent>
      </Card>

      {/* Backtesting section */}
      {trade.source === 'SIMULATOR' && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Backtesting</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <dl className="grid grid-cols-2 sm:grid-cols-4 gap-x-6 gap-y-3">
              <Field
                label="Capital inicial"
                value={trade.capitalInicial != null ? `$${trade.capitalInicial.toFixed(2)}` : null}
              />
              <Field
                label="Risco %"
                value={trade.riskPct != null ? `${trade.riskPct.toFixed(2)}%` : null}
              />
              <Field
                label="Lote"
                value={trade.lotSize != null ? trade.lotSize.toFixed(2) : null}
              />
              <Field label="Duração" value="—" />
            </dl>

            <dl className="grid grid-cols-3 gap-x-6 gap-y-3">
              <Field
                label="SL pts"
                value={trade.slPoints != null ? Math.round(trade.slPoints).toString() : slPts}
              />
              <Field
                label="TP pts"
                value={trade.tpPoints != null ? Math.round(trade.tpPoints).toString() : tpPts}
              />
              <Field
                label="PnL líquido"
                value={trade.pnlNet != null ? `$${trade.pnlNet.toFixed(2)}` : null}
              />
            </dl>

            <div>
              <p className="text-xs text-muted-foreground mb-2">MAE / MFE</p>
              <div className="grid grid-cols-2 gap-4 mb-3">
                <div className="rounded-lg border p-3 text-center">
                  <p className="text-xs text-muted-foreground mb-1">MFE pts</p>
                  <p className="text-2xl font-bold tabular-nums">
                    {trade.mfePoints != null ? trade.mfePoints : '—'}
                  </p>
                </div>
                <div className="rounded-lg border p-3 text-center">
                  <p className="text-xs text-muted-foreground mb-1">MAE pts</p>
                  <p className="text-2xl font-bold tabular-nums">
                    {trade.maePoints != null ? trade.maePoints : '—'}
                  </p>
                </div>
              </div>
              <p className="text-xs text-muted-foreground mb-2">Níveis atingidos</p>
              <div className="flex gap-3">
                {hitLevels.map(({ label, hit }) => (
                  <span key={label} className="text-sm font-medium tabular-nums">
                    {hit === true ? '✅' : hit === false ? '❌' : '–'} {label}
                  </span>
                ))}
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* MAE / MFE card */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">MAE / MFE</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="rounded-lg border p-3 text-center">
              <p className="text-xs text-muted-foreground mb-1">MFE pts</p>
              <p className="text-2xl font-bold tabular-nums">
                {trade.mfePoints != null ? trade.mfePoints : '—'}
              </p>
            </div>
            <div className="rounded-lg border p-3 text-center">
              <p className="text-xs text-muted-foreground mb-1">MAE pts</p>
              <p className="text-2xl font-bold tabular-nums">
                {trade.maePoints != null ? trade.maePoints : '—'}
              </p>
            </div>
          </div>

          {/* Hit levels */}
          <div>
            <p className="text-xs text-muted-foreground mb-2">Níveis atingidos</p>
            <div className="flex gap-3">
              {hitLevels.map(({ label, hit }) => (
                <span key={label} className="text-sm font-medium tabular-nums">
                  {hit === true ? '✅' : hit === false ? '❌' : '–'} {label}
                </span>
              ))}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Notes */}
      {trade.notes && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Notas</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm whitespace-pre-wrap">{trade.notes}</p>
          </CardContent>
        </Card>
      )}

      {/* Screenshot */}
      {trade.screenshotUrl && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Screenshot</CardTitle>
          </CardHeader>
          <CardContent>
            <img
              src={trade.screenshotUrl}
              alt="Screenshot do trade"
              className="rounded border max-w-full"
            />
          </CardContent>
        </Card>
      )}
    </div>
  )
}
