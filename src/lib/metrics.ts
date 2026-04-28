import type { Trade } from '@prisma/client'

export type WinRateInfo = { count: number; wins: number; rate: number | null }

export function winRateOf(trades: Trade[]): WinRateInfo {
  const counted = trades.filter((t) => t.result !== 'BREAKEVEN')
  const wins = counted.filter((t) => t.result === 'WIN').length
  return {
    count: counted.length,
    wins,
    rate: counted.length === 0 ? null : wins / counted.length,
  }
}

export function sumR(trades: Trade[]): number {
  return trades.reduce((s, t) => s + t.rrAchieved, 0)
}

export function avgR(trades: Trade[]): number | null {
  if (trades.length === 0) return null
  return sumR(trades) / trades.length
}

export function profitFactor(trades: Trade[]): number | null {
  const wins = trades.filter((t) => t.rrAchieved > 0).reduce((s, t) => s + t.rrAchieved, 0)
  const losses = trades.filter((t) => t.rrAchieved < 0).reduce((s, t) => s + Math.abs(t.rrAchieved), 0)
  if (losses === 0) return wins === 0 ? null : Infinity
  return wins / losses
}

export type StreakInfo = { current: number; currentType: 'WIN' | 'LOSS' | null; longestWin: number; longestLoss: number }

export function streaks(tradesChronological: Trade[]): StreakInfo {
  let longestWin = 0
  let longestLoss = 0
  let runWin = 0
  let runLoss = 0

  for (const t of tradesChronological) {
    if (t.result === 'WIN') {
      runWin++
      runLoss = 0
      if (runWin > longestWin) longestWin = runWin
    } else if (t.result === 'LOSS') {
      runLoss++
      runWin = 0
      if (runLoss > longestLoss) longestLoss = runLoss
    } else {
      runWin = 0
      runLoss = 0
    }
  }

  let current = 0
  let currentType: 'WIN' | 'LOSS' | null = null
  for (let i = tradesChronological.length - 1; i >= 0; i--) {
    const r = tradesChronological[i].result
    if (r === 'BREAKEVEN') break
    if (currentType === null) currentType = r
    if (r !== currentType) break
    current++
  }

  return { current, currentType, longestWin, longestLoss }
}

export function maxDrawdownR(tradesChronological: Trade[]): number {
  let peak = 0
  let cum = 0
  let maxDD = 0
  for (const t of tradesChronological) {
    cum += t.rrAchieved
    if (cum > peak) peak = cum
    const dd = peak - cum
    if (dd > maxDD) maxDD = dd
  }
  return maxDD
}

export type RrLevel = { level: number; eligible: number; hit: number; rate: number | null }

export function rrRetro(trades: Trade[]): RrLevel[] {
  const fields = ['hit1R', 'hit2R', 'hit3R', 'hit4R', 'hit5R'] as const
  return fields.map((field, idx) => {
    const eligibleTrades = trades.filter((t) => t[field] !== null && t[field] !== undefined)
    const hit = eligibleTrades.filter((t) => t[field] === true).length
    return {
      level: idx + 1,
      eligible: eligibleTrades.length,
      hit,
      rate: eligibleTrades.length === 0 ? null : hit / eligibleTrades.length,
    }
  })
}

export function mfeVsAchieved(trades: Trade[]): { avgMfeR: number | null; avgAchievedR: number | null; sample: number } {
  const withMfe = trades.filter((t) => t.rrPotential != null)
  if (withMfe.length === 0) return { avgMfeR: null, avgAchievedR: null, sample: 0 }
  const avgMfe = withMfe.reduce((s, t) => s + (t.rrPotential ?? 0), 0) / withMfe.length
  const avgAch = withMfe.reduce((s, t) => s + t.rrAchieved, 0) / withMfe.length
  return { avgMfeR: avgMfe, avgAchievedR: avgAch, sample: withMfe.length }
}

export function monthRange(date: Date): { start: Date; end: Date } {
  const start = new Date(date.getFullYear(), date.getMonth(), 1)
  const end = new Date(date.getFullYear(), date.getMonth() + 1, 1)
  return { start, end }
}

export function previousMonthRange(date: Date): { start: Date; end: Date } {
  const start = new Date(date.getFullYear(), date.getMonth() - 1, 1)
  const end = new Date(date.getFullYear(), date.getMonth(), 1)
  return { start, end }
}
