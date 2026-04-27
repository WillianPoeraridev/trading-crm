import Link from 'next/link'
import { prisma } from '@/lib/prisma'
import { buttonVariants } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { format } from 'date-fns'

export const dynamic = 'force-dynamic'

export default async function TradesPage() {
  const trades = await prisma.trade.findMany({
    include: { pattern: true },
    orderBy: { entryTime: 'desc' },
  })

  return (
    <div className="max-w-5xl mx-auto space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Trades</h1>
        <Link href="/trades/new" className={buttonVariants()}>Novo Trade</Link>
      </div>

      {trades.length === 0 ? (
        <p className="text-muted-foreground text-center py-16">
          Nenhum trade registrado ainda.{' '}
          <Link href="/trades/new" className="underline">
            Registrar o primeiro
          </Link>
          .
        </p>
      ) : (
        <div className="border rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-muted/50">
              <tr>
                <th className="text-left px-4 py-3">Data</th>
                <th className="text-left px-4 py-3">Instrumento</th>
                <th className="text-left px-4 py-3">Direção</th>
                <th className="text-left px-4 py-3">Padrão</th>
                <th className="text-right px-4 py-3">R Planejado</th>
                <th className="text-right px-4 py-3">R Obtido</th>
                <th className="text-left px-4 py-3">Resultado</th>
              </tr>
            </thead>
            <tbody>
              {trades.map((trade) => (
                <tr key={trade.id} className="border-t hover:bg-muted/30">
                  <td className="px-4 py-3">
                    <Link href={`/trades/${trade.id}`} className="hover:underline">
                      {format(new Date(trade.entryTime), 'dd/MM/yyyy HH:mm')}
                    </Link>
                  </td>
                  <td className="px-4 py-3">{trade.instrument}</td>
                  <td className="px-4 py-3">
                    <Badge variant={trade.direction === 'LONG' ? 'default' : 'secondary'}>
                      {trade.direction}
                    </Badge>
                  </td>
                  <td className="px-4 py-3">{trade.pattern.name}</td>
                  <td className="px-4 py-3 text-right">{trade.rrPlanned.toFixed(2)}R</td>
                  <td className="px-4 py-3 text-right">{trade.rrAchieved.toFixed(2)}R</td>
                  <td className="px-4 py-3">
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
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
