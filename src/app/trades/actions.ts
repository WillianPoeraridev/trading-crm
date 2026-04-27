'use server'

import { redirect } from 'next/navigation'
import { prisma } from '@/lib/prisma'
import { z } from 'zod'

const tradeSchema = z.object({
  instrument: z.string().default('NAS100'),
  direction: z.enum(['LONG', 'SHORT']),
  entryTime: z.string(),
  entryPrice: z.coerce.number(),
  stopPrice: z.coerce.number(),
  targetPrice: z.coerce.number(),
  exitPrice: z.coerce.number(),
  mfePrice: z.coerce.number().optional().nullable(),
  patternId: z.string().min(1, 'Selecione um padrão'),
  screenshotUrl: z.string().optional().nullable(),
  notes: z.string().optional().nullable(),
})

function calcRR(direction: 'LONG' | 'SHORT', entry: number, stop: number, target: number, exit: number, mfe?: number | null) {
  const risk = direction === 'LONG' ? entry - stop : stop - entry
  if (risk <= 0) throw new Error('Stop inválido em relação à entrada')

  const sign = direction === 'LONG' ? 1 : -1
  const rrPlanned = (sign * (target - entry)) / risk
  const rrAchieved = (sign * (exit - entry)) / risk
  const rrPotential = mfe != null ? (sign * (mfe - entry)) / risk : null

  const result =
    rrAchieved > 0.05 ? 'WIN' : rrAchieved < -0.05 ? 'LOSS' : 'BREAKEVEN'

  return { rrPlanned, rrAchieved, rrPotential, result } as const
}

export async function createTrade(formData: FormData) {
  const raw = Object.fromEntries(formData.entries())
  const parsed = tradeSchema.safeParse({
    ...raw,
    mfePrice: raw.mfePrice ? raw.mfePrice : null,
    screenshotUrl: raw.screenshotUrl || null,
    notes: raw.notes || null,
  })

  if (!parsed.success) {
    throw new Error(parsed.error.issues.map((i) => i.message).join(', '))
  }

  const d = parsed.data
  const { rrPlanned, rrAchieved, rrPotential, result } = calcRR(
    d.direction,
    d.entryPrice,
    d.stopPrice,
    d.targetPrice,
    d.exitPrice,
    d.mfePrice,
  )

  await prisma.trade.create({
    data: {
      instrument: d.instrument,
      direction: d.direction,
      entryTime: new Date(d.entryTime),
      entryPrice: d.entryPrice,
      stopPrice: d.stopPrice,
      targetPrice: d.targetPrice,
      exitPrice: d.exitPrice,
      mfePrice: d.mfePrice ?? null,
      rrPlanned,
      rrAchieved,
      rrPotential,
      result,
      patternId: d.patternId,
      screenshotUrl: d.screenshotUrl ?? null,
      notes: d.notes ?? null,
    },
  })

  redirect('/trades')
}

export async function getPatterns() {
  return prisma.pattern.findMany({ orderBy: { name: 'asc' } })
}
