import { NextRequest } from 'next/server'
import { z } from 'zod'
import { prisma } from '@/lib/prisma'
import { calcRR } from '@/lib/calcRR'

const tradeSchema = z.object({
  instrument: z.string().default('NAS100'),
  direction: z.enum(['LONG', 'SHORT']),
  source: z.enum(['SIMULATOR', 'REAL']),
  exitReason: z.enum(['SL', 'TP', 'MANUAL']),
  entryTime: z.string().datetime(),
  sessionDate: z.string().datetime().nullable().optional(),
  entryPrice: z.number(),
  stopPrice: z.number(),
  targetPrice: z.number(),
  exitPrice: z.number(),
  mfePoints: z.number().nullable().optional(),
  mae: z.number().nullable().optional(),
  maePoints: z.number().nullable().optional(),
  contractsQty: z.number().int().positive().default(1),
  commission: z.number().nullable().optional(),
  pnlGross: z.number().nullable().optional(),
  pnlNet: z.number().nullable().optional(),
  ratingSetup: z.number().int().min(1).max(5).nullable().optional(),
  ratingExecution: z.number().int().min(1).max(5).nullable().optional(),
  followedPlan: z.boolean().default(false),
  tags: z.string().nullable().optional(),
  hit1R: z.boolean().nullable().optional(),
  hit2R: z.boolean().nullable().optional(),
  hit3R: z.boolean().nullable().optional(),
  hit4R: z.boolean().nullable().optional(),
  hit5R: z.boolean().nullable().optional(),
  patternId: z.string().nullable().optional(),
  screenshotUrl: z.string().url().nullable().optional(),
  notes: z.string().nullable().optional(),
  capitalInicial: z.number().nullable().optional(),
  riskPct: z.number().nullable().optional(),
  lotSize: z.number().nullable().optional(),
  slPoints: z.number().nullable().optional(),
  tpPoints: z.number().nullable().optional(),
})

export async function POST(request: NextRequest) {
  const apiKey = request.headers.get('x-api-key')
  if (!apiKey || apiKey !== process.env.API_KEY) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 })
  }

  let body: unknown
  try {
    body = await request.json()
  } catch {
    return Response.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  const parsed = tradeSchema.safeParse(body)
  if (!parsed.success) {
    return Response.json(
      { error: 'Validation error', issues: parsed.error.issues },
      { status: 400 },
    )
  }

  const d = parsed.data

  const mfePrice =
    d.mfePoints != null
      ? d.direction === 'LONG'
        ? d.entryPrice + d.mfePoints * 0.01
        : d.entryPrice - d.mfePoints * 0.01
      : null

  let rrPlanned: number
  let rrAchieved: number
  let rrPotential: number | null
  let result: 'WIN' | 'LOSS' | 'BREAKEVEN'

  try {
    ;({ rrPlanned, rrAchieved, rrPotential, result } = calcRR(
      d.direction,
      d.entryPrice,
      d.stopPrice,
      d.targetPrice,
      d.exitPrice,
      mfePrice,
    ))
  } catch (err) {
    return Response.json(
      { error: err instanceof Error ? err.message : 'Erro no cálculo de RR' },
      { status: 400 },
    )
  }

  const trade = await prisma.trade.create({
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
      capitalInicial: d.capitalInicial ?? null,
      riskPct: d.riskPct ?? null,
      lotSize: d.lotSize ?? null,
      slPoints: d.slPoints ?? null,
      tpPoints: d.tpPoints ?? null,
    },
  })

  return Response.json(trade, { status: 201 })
}
