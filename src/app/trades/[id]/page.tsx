import { notFound } from 'next/navigation'
import Link from 'next/link'
import { prisma } from '@/lib/prisma'
import { Badge } from '@/components/ui/badge'
import { buttonVariants } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { format } from 'date-fns'

export const dynamic = 'force-dynamic'

export default async function TradePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const trade = await prisma.trade.findUnique({
    where: { id },
    include: { pattern: true },
  })

  if (!trade) notFound()

  const fields = [
    { label: 'Instrumento', value: trade.instrument },
    { label: 'Direção', value: trade.direction },
    { label: 'Entrada', value: format(new Date(trade.entryTime), 'dd/MM/yyyy HH:mm') },
    { label: 'Preço entrada', value: trade.entryPrice },
    { label: 'Stop', value: trade.stopPrice },
    { label: 'Alvo', value: trade.targetPrice },
    { label: 'Preço saída', value: trade.exitPrice },
    { label: 'MFE', value: trade.mfePrice ?? '—' },
    { label: 'R Planejado', value: `${trade.rrPlanned.toFixed(2)}R` },
    { label: 'R Obtido', value: `${trade.rrAchieved.toFixed(2)}R` },
    { label: 'R Potencial', value: trade.rrPotential ? `${trade.rrPotential.toFixed(2)}R` : '—' },
    { label: 'Padrão', value: trade.pattern.name },
    { label: 'Resultado', value: trade.result },
  ]

  return (
    <div className="max-w-2xl mx-auto space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Trade</h1>
        <Link href="/trades" className={buttonVariants({ variant: 'outline' })}>Voltar</Link>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
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
          </CardTitle>
        </CardHeader>
        <CardContent>
          <dl className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
            {fields.map(({ label, value }) => (
              <div key={label}>
                <dt className="text-muted-foreground">{label}</dt>
                <dd className="font-medium">{String(value)}</dd>
              </div>
            ))}
          </dl>

          {trade.notes && (
            <div className="mt-4">
              <p className="text-muted-foreground text-sm mb-1">Notas</p>
              <p className="text-sm whitespace-pre-wrap">{trade.notes}</p>
            </div>
          )}

          {trade.screenshotUrl && (
            <div className="mt-4">
              <p className="text-muted-foreground text-sm mb-2">Screenshot</p>
              <img
                src={trade.screenshotUrl}
                alt="Screenshot do trade"
                className="rounded border max-w-full"
              />
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
