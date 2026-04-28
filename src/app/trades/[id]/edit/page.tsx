import { notFound } from 'next/navigation'
import Link from 'next/link'
import { prisma } from '@/lib/prisma'
import { buttonVariants } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { updateTrade } from './actions'

export const dynamic = 'force-dynamic'

export default async function EditTradePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const trade = await prisma.trade.findUnique({
    where: { id },
    select: { id: true, instrument: true, notes: true, screenshotUrl: true },
  })

  if (!trade) notFound()

  const updateWithId = updateTrade.bind(null, id)

  return (
    <div className="max-w-lg mx-auto space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Editar Trade</h1>
        <Link href={`/trades/${id}`} className={buttonVariants({ variant: 'ghost' })}>
          Cancelar
        </Link>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{trade.instrument}</CardTitle>
        </CardHeader>
        <CardContent>
          <form action={updateWithId} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="screenshotUrl">URL do Screenshot</Label>
              <Input
                id="screenshotUrl"
                name="screenshotUrl"
                type="text"
                defaultValue={trade.screenshotUrl ?? ''}
                placeholder="https://..."
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="notes">Notas</Label>
              <Textarea
                id="notes"
                name="notes"
                rows={5}
                defaultValue={trade.notes ?? ''}
                placeholder="Observações sobre o trade..."
              />
            </div>

            <div className="flex justify-end gap-2">
              <Link href={`/trades/${id}`} className={buttonVariants({ variant: 'outline' })}>
                Cancelar
              </Link>
              <button type="submit" className={buttonVariants()}>
                Salvar
              </button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
