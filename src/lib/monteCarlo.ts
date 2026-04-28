export type MonteCarloInput = {
  winRate: number
  avgRR: number
  trials?: number
  daysPerTrial?: number
  tradesPerDay?: number
  startCapital: number
  riskPercent: number
  targetCapital: number
}

export type MonteCarloResult = {
  trials: number
  finals: number[]
  median: number
  mean: number
  pHitTarget: number
  pBelowStart: number
  pHalfDestroyed: number
  pTotalDestroyed: number
  histogram: HistogramBin[]
  startCapital: number
  targetCapital: number
}

export type HistogramBin = {
  label: string
  min: number
  max: number
  count: number
  fraction: number
  band: 'destroyed' | 'belowStart' | 'profit' | 'target'
  color: string
}

export const BAND_COLORS = {
  destroyed: '#dc2626',
  belowStart: '#9ca3af',
  profit: '#16a34a',
  target: '#15803d',
} as const

function bandFor(value: number, startCapital: number, targetCapital: number): HistogramBin['band'] {
  if (value <= startCapital * 0.5) return 'destroyed'
  if (value < startCapital) return 'belowStart'
  if (value < targetCapital) return 'profit'
  return 'target'
}

export function runMonteCarlo({
  winRate,
  avgRR,
  trials = 2000,
  daysPerTrial = 30,
  tradesPerDay = 1,
  startCapital,
  riskPercent,
  targetCapital,
}: MonteCarloInput): MonteCarloResult {
  const wr = Math.max(0, Math.min(1, winRate))
  const trades = daysPerTrial * tradesPerDay
  const finals: number[] = new Array(trials)

  for (let i = 0; i < trials; i++) {
    let capital = startCapital
    for (let t = 0; t < trades; t++) {
      const risk = capital * riskPercent
      const win = Math.random() < wr
      capital += win ? risk * avgRR : -risk
      if (capital <= 0) {
        capital = 0
        break
      }
    }
    finals[i] = capital
  }

  const sorted = [...finals].sort((a, b) => a - b)
  const median = sorted[Math.floor(trials / 2)]
  const mean = finals.reduce((s, v) => s + v, 0) / trials
  const pHitTarget = finals.filter((v) => v >= targetCapital).length / trials
  const pBelowStart = finals.filter((v) => v < startCapital).length / trials
  const pHalfDestroyed = finals.filter((v) => v <= startCapital * 0.5).length / trials
  const pTotalDestroyed = finals.filter((v) => v <= 0).length / trials

  const histogram = buildHistogram(sorted, startCapital, targetCapital)

  return {
    trials,
    finals,
    median,
    mean,
    pHitTarget,
    pBelowStart,
    pHalfDestroyed,
    pTotalDestroyed,
    histogram,
    startCapital,
    targetCapital,
  }
}

function buildHistogram(sorted: number[], startCapital: number, targetCapital: number): HistogramBin[] {
  const trials = sorted.length
  const min = 0
  const max = Math.max(sorted[sorted.length - 1], targetCapital * 1.5)
  const binCount = 24
  const step = (max - min) / binCount

  const bins: HistogramBin[] = []
  for (let i = 0; i < binCount; i++) {
    const lo = min + i * step
    const hi = i === binCount - 1 ? max : min + (i + 1) * step
    const center = (lo + hi) / 2
    const band = bandFor(center, startCapital, targetCapital)
    bins.push({
      label: `$${Math.round(center)}`,
      min: lo,
      max: hi,
      count: 0,
      fraction: 0,
      band,
      color: BAND_COLORS[band],
    })
  }

  for (const v of sorted) {
    let idx = Math.floor((v - min) / step)
    if (idx >= binCount) idx = binCount - 1
    if (idx < 0) idx = 0
    bins[idx].count++
  }
  for (const b of bins) b.fraction = b.count / trials

  return bins
}
