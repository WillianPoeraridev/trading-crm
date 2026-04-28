'use server'

import { redirect } from 'next/navigation'
import { z } from 'zod'
import { prisma } from '@/lib/prisma'
import { calcRR } from '@/lib/calcRR'

// Preprocess helpers for CSV string values
const numOrNull = z.preprocess(
  (v) => (v === '' || v == null ? null : Number(v)),
  z.number().nullable().optional(),
)
const intOrNull = z.preprocess(
  (v) => (v === '' || v == null ? null : Number(v)),
  z.number().int().nullable().optional(),
)
const boolOrNull = z.preprocess(
  (v) => (v === 'true' ? true : v === 'false' ? false : null),
  z.boolean().nullable().optional(),
)
const strOrNull = z.preprocess(
  (v) => (v === '' || v == null ? null : String(v)),
  z.string().nullable().optional(),
)

const csvTradeSchema = z.object({
  instrument: z.string().default('NAS100'),
  direction: z.enum(['LONG', 'SHORT']),
  source: z.enum(['SIMULATOR', 'REAL']),
  exitReason: z.enum(['SL', 'TP', 'MANUAL']),
  entryTime: z.string().datetime(),
  sessionDate: z.preprocess(
    (v) => (v === '' || v == null ? null : v),
    z.string().datetime().nullable().optional(),
  ),
  entryPrice: z.coerce.number(),
  stopPrice: z.coerce.number(),
  targetPrice: z.coerce.number(),
  exitPrice: z.coerce.number(),
  mfePoints: numOrNull,
  mae: numOrNull,
  maePoints: numOrNull,
  contractsQty: z.coerce.number().int().positive().default(1),
  commission: numOrNull,
  pnlGross: numOrNull,
  pnlNet: numOrNull,
  ratingSetup: intOrNull,
  ratingExecution: intOrNull,
  followedPlan: z.preprocess((v) => v === 'true', z.boolean()).default(false),
  tags: strOrNull,
  hit1R: boolOrNull,
  hit2R: boolOrNull,
  hit3R: boolOrNull,
  hit4R: boolOrNull,
  hit5R: boolOrNull,
  patternId: strOrNull,
  screenshotUrl: strOrNull,
  notes: strOrNull,
})

function parseCSV(text: string): Record<string, string>[] {
  const lines = text.trim().split(/\r?\n/)
  if (lines.length < 2) return []
  const headers = lines[0].split(',').map((h) => h.trim().replace(/^"|"$/g, ''))
  return lines.slice(1).map((line) => {
    const values = line.split(',').map((v) => v.trim().replace(/^"|"$/g, ''))
    return Object.fromEntries(headers.map((h, i) => [h, values[i] ?? '']))
  })
}

export async function importCsv(formData: FormData) {
  const file = formData.get('file') as File | null
  if (!file) redirect('/trades/import-csv?imported=0&errors=0')

  const text = await file.text()
  const rows = parseCSV(text)

  let imported = 0
  let errors = 0

  for (const row of rows) {
    const parsed = csvTradeSchema.safeParse(row)
    if (!parsed.success) {
      errors++
      continue
    }

    const d = parsed.data

    const mfePrice =
      d.mfePoints != null
        ? d.direction === 'LONG'
          ? d.entryPrice + d.mfePoints
          : d.entryPrice - d.mfePoints
        : null

    try {
      const { rrPlanned, rrAchieved, rrPotential, result } = calcRR(
        d.direction,
        d.entryPrice,
        d.stopPrice,
        d.targetPrice,
        d.exitPrice,
        mfePrice,
      )

      await prisma.trade.create({
        data: {
          instrument: d.instrument,
          direction: d.direction,
          source: d.source,
          exitReason: d.exitReason,
          entryTime: new Date(d.entryTime),
          sessionDate: d.sessionDate ? new Date(d.sessionDate) : null,
          entryPrice: d.entryPrice,
          stopPrice: d.stopPrice,
          targetPrice: d.targetPrice,
          exitPrice: d.exitPrice,
          mfePrice,
          mfePoints: d.mfePoints ?? null,
          mae: d.mae ?? null,
          maePoints: d.maePoints ?? null,
          rrPlanned,
          rrAchieved,
          rrPotential,
          result,
          contractsQty: d.contractsQty,
          commission: d.commission ?? null,
          pnlGross: d.pnlGross ?? null,
          pnlNet: d.pnlNet ?? null,
          ratingSetup: d.ratingSetup ?? null,
          ratingExecution: d.ratingExecution ?? null,
          followedPlan: d.followedPlan,
          tags: d.tags ?? null,
          hit1R: d.hit1R ?? null,
          hit2R: d.hit2R ?? null,
          hit3R: d.hit3R ?? null,
          hit4R: d.hit4R ?? null,
          hit5R: d.hit5R ?? null,
          patternId: d.patternId ?? null,
          screenshotUrl: d.screenshotUrl ?? null,
          notes: d.notes ?? null,
        },
      })
      imported++
    } catch {
      errors++
    }
  }

  redirect(`/trades/import-csv?imported=${imported}&errors=${errors}`)
}
