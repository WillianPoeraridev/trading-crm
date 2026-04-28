import Link from 'next/link'
import { buttonVariants } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { importCsv } from './actions'

export const dynamic = 'force-dynamic'

export default async function ImportCsvPage({
  searchParams,
}: {
  searchParams: Promise<{ imported?: string; errors?: string }>
}) {
  const { imported, errors } = await searchParams
  const hasResult = imported !== undefined

  return (
    <div className="max-w-lg mx-auto space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Importar CSV</h1>
        <Link href="/trades" className={buttonVariants({ variant: 'ghost' })}>
          Voltar
        </Link>
      </div>

      {hasResult && (
        <div className="rounded-lg border p-4 text-sm space-y-1">
          <p className="font-semibold">Importação concluída</p>
          <p className="text-muted-foreground">
            {imported} trade(s) importado(s) com sucesso
            {Number(errors) > 0 && `, ${errors} linha(s) com erro`}.
          </p>
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Selecionar arquivo</CardTitle>
        </CardHeader>
        <CardContent>
          <form action={importCsv} encType="multipart/form-data" className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="file">Arquivo CSV</Label>
              <input
                id="file"
                name="file"
                type="file"
                accept=".csv"
                required
                className="block w-full text-sm file:mr-4 file:py-1.5 file:px-3 file:rounded file:border-0 file:text-xs file:font-medium file:bg-muted file:text-muted-foreground hover:file:bg-muted/80"
              />
            </div>

            <p className="text-xs text-muted-foreground">
              O CSV deve ter as mesmas colunas do payload da API:{' '}
              <code className="font-mono">
                instrument, direction, source, exitReason, entryTime, entryPrice, stopPrice,
                targetPrice, exitPrice, …
              </code>
            </p>

            <button type="submit" className={buttonVariants()}>
              Importar
            </button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
