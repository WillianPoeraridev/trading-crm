'use client'

import { useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Card, CardContent } from '@/components/ui/card'
import { createTrade } from '../actions'

type Pattern = { id: string; name: string }

interface Props {
  patterns: Pattern[]
}

function calcRR(
  direction: 'LONG' | 'SHORT',
  entry: number,
  stop: number,
  target: number,
  exit: number,
  mfe?: number,
) {
  const risk = direction === 'LONG' ? entry - stop : stop - entry
  if (risk <= 0) return null

  const sign = direction === 'LONG' ? 1 : -1
  return {
    rrPlanned: (sign * (target - entry)) / risk,
    rrAchieved: (sign * (exit - entry)) / risk,
    rrPotential: mfe != null && !isNaN(mfe) ? (sign * (mfe - entry)) / risk : null,
  }
}

function fmt(n: number | null | undefined) {
  if (n == null) return '—'
  return `${n > 0 ? '+' : ''}${n.toFixed(2)}R`
}

export function TradeForm({ patterns }: Props) {
  const router = useRouter()
  const [direction, setDirection] = useState<'LONG' | 'SHORT'>('LONG')
  const [entry, setEntry] = useState('')
  const [stop, setStop] = useState('')
  const [target, setTarget] = useState('')
  const [exit, setExit] = useState('')
  const [mfe, setMfe] = useState('')
  const [uploading, setUploading] = useState(false)
  const [screenshotUrl, setScreenshotUrl] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  const n = (v: string) => parseFloat(v)
  const rr =
    entry && stop && target && exit
      ? calcRR(direction, n(entry), n(stop), n(target), n(exit), mfe ? n(mfe) : undefined)
      : null

  const result =
    rr == null
      ? '—'
      : rr.rrAchieved > 0.05
      ? 'WIN'
      : rr.rrAchieved < -0.05
      ? 'LOSS'
      : 'BREAKEVEN'

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setUploading(true)
    const fd = new FormData()
    fd.append('file', file)
    const res = await fetch('/api/upload', { method: 'POST', body: fd })
    const data = await res.json()
    setScreenshotUrl(data.url ?? '')
    setUploading(false)
  }

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError('')
    setSubmitting(true)
    try {
      const fd = new FormData(e.currentTarget)
      if (screenshotUrl) fd.set('screenshotUrl', screenshotUrl)
      await createTrade(fd)
    } catch (err: unknown) {
      if (err instanceof Error && err.message !== 'NEXT_REDIRECT') {
        setError(err.message)
      }
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {error && (
        <div className="bg-destructive/10 text-destructive text-sm px-4 py-3 rounded border border-destructive/20">
          {error}
        </div>
      )}

      <Card>
        <CardContent className="pt-6 grid grid-cols-2 gap-4">
          <div className="col-span-2">
            <Label>Instrumento</Label>
            <Input name="instrument" defaultValue="NAS100" readOnly className="bg-muted" />
          </div>

          <div className="col-span-2">
            <Label>Direção</Label>
            <div className="flex gap-2 mt-1">
              {(['LONG', 'SHORT'] as const).map((d) => (
                <button
                  key={d}
                  type="button"
                  onClick={() => setDirection(d)}
                  className={`flex-1 py-2 rounded border text-sm font-medium transition-colors ${
                    direction === d
                      ? d === 'LONG'
                        ? 'bg-green-600 text-white border-green-600'
                        : 'bg-red-600 text-white border-red-600'
                      : 'bg-background hover:bg-muted'
                  }`}
                >
                  {d}
                </button>
              ))}
              <input type="hidden" name="direction" value={direction} />
            </div>
          </div>

          <div className="col-span-2">
            <Label htmlFor="entryTime">Data/Hora Entrada</Label>
            <Input id="entryTime" name="entryTime" type="datetime-local" required />
          </div>

          <div>
            <Label htmlFor="entryPrice">Preço Entrada</Label>
            <Input
              id="entryPrice"
              name="entryPrice"
              type="number"
              step="any"
              required
              value={entry}
              onChange={(e) => setEntry(e.target.value)}
            />
          </div>

          <div>
            <Label htmlFor="stopPrice">Stop</Label>
            <Input
              id="stopPrice"
              name="stopPrice"
              type="number"
              step="any"
              required
              value={stop}
              onChange={(e) => setStop(e.target.value)}
            />
          </div>

          <div>
            <Label htmlFor="targetPrice">Alvo</Label>
            <Input
              id="targetPrice"
              name="targetPrice"
              type="number"
              step="any"
              required
              value={target}
              onChange={(e) => setTarget(e.target.value)}
            />
          </div>

          <div>
            <Label htmlFor="exitPrice">Preço Saída</Label>
            <Input
              id="exitPrice"
              name="exitPrice"
              type="number"
              step="any"
              required
              value={exit}
              onChange={(e) => setExit(e.target.value)}
            />
          </div>

          <div className="col-span-2">
            <Label htmlFor="mfePrice">MFE (opcional)</Label>
            <Input
              id="mfePrice"
              name="mfePrice"
              type="number"
              step="any"
              value={mfe}
              onChange={(e) => setMfe(e.target.value)}
            />
          </div>

          <div className="col-span-2">
            <Label htmlFor="patternId">Padrão</Label>
            <select
              id="patternId"
              name="patternId"
              required
              className="w-full mt-1 h-9 rounded-md border bg-background px-3 py-1 text-sm shadow-sm focus:outline-none focus:ring-1 focus:ring-ring"
            >
              <option value="">Selecione um padrão...</option>
              {patterns.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </div>

          <div className="col-span-2">
            <Label>Screenshot</Label>
            <Input
              ref={fileRef}
              type="file"
              accept="image/*"
              onChange={handleUpload}
              className="mt-1"
            />
            {uploading && <p className="text-xs text-muted-foreground mt-1">Enviando...</p>}
            {screenshotUrl && (
              <p className="text-xs text-green-600 mt-1">Upload concluído.</p>
            )}
          </div>

          <div className="col-span-2">
            <Label htmlFor="notes">Notas</Label>
            <Textarea id="notes" name="notes" rows={4} placeholder="Observações sobre o trade..." />
          </div>
        </CardContent>
      </Card>

      {/* R:R em tempo real */}
      <Card className="bg-muted/30">
        <CardContent className="pt-6 grid grid-cols-3 gap-4 text-center">
          <div>
            <p className="text-xs text-muted-foreground mb-1">R Planejado</p>
            <p className="text-lg font-mono font-semibold">{rr ? fmt(rr.rrPlanned) : '—'}</p>
          </div>
          <div>
            <p className="text-xs text-muted-foreground mb-1">R Obtido</p>
            <p
              className={`text-lg font-mono font-semibold ${
                rr && rr.rrAchieved > 0.05
                  ? 'text-green-600'
                  : rr && rr.rrAchieved < -0.05
                  ? 'text-red-600'
                  : ''
              }`}
            >
              {rr ? fmt(rr.rrAchieved) : '—'}
            </p>
          </div>
          <div>
            <p className="text-xs text-muted-foreground mb-1">R Potencial (MFE)</p>
            <p className="text-lg font-mono font-semibold">{rr ? fmt(rr.rrPotential) : '—'}</p>
          </div>
          <div className="col-span-3">
            <p className="text-xs text-muted-foreground mb-1">Resultado</p>
            <p
              className={`text-base font-semibold ${
                result === 'WIN'
                  ? 'text-green-600'
                  : result === 'LOSS'
                  ? 'text-red-600'
                  : 'text-muted-foreground'
              }`}
            >
              {result}
            </p>
          </div>
        </CardContent>
      </Card>

      <div className="flex gap-3">
        <Button type="submit" disabled={submitting || uploading} className="flex-1">
          {submitting ? 'Salvando...' : 'Salvar Trade'}
        </Button>
        <Button
          type="button"
          variant="outline"
          onClick={() => router.push('/trades')}
        >
          Cancelar
        </Button>
      </div>
    </form>
  )
}
