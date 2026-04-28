export function calcRR(
  direction: 'LONG' | 'SHORT',
  entry: number,
  stop: number,
  target: number,
  exit: number,
  mfe?: number | null,
) {
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
