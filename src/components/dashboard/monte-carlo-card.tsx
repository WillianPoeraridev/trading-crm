'use client'

import { useMemo, useState } from 'react'
import { BarChart, Bar, Cell, ResponsiveContainer, XAxis, YAxis, Tooltip, ReferenceLine } from 'recharts'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { runMonteCarlo, BAND_COLORS } from '@/lib/monteCarlo'

type Props = {
  totalTrades: number
  autoWinRate: number | null
  autoAvgRR: number | null
}

const START_CAPITAL = 600
const TARGET_CAPITAL = 1800
const RISK_PERCENT = 0.14
const TRIALS = 2000
const DAYS = 30

export function MonteCarloCard({ totalTrades, autoWinRate, autoAvgRR }: Props) {
  const auto = totalTrades >= 20 && autoWinRate != null && autoAvgRR != null && autoAvgRR > 0

  const [manualWinPct, setManualWinPct] = useState('45')
  const [manualRR, setManualRR] = useState('1.5')
  const [manualResult, setManualResult] = useState<ReturnType<typeof runMonteCarlo> | null>(null)

  const autoResult = useMemo(() => {
    if (!auto) return null
    return runMonteCarlo({
      winRate: autoWinRate!,
      avgRR: autoAvgRR!,
      trials: TRIALS,
      daysPerTrial: DAYS,
      startCapital: START_CAPITAL,
      riskPercent: RISK_PERCENT,
      targetCapital: TARGET_CAPITAL,
    })
  }, [auto, autoWinRate, autoAvgRR])

  const result = auto ? autoResult : manualResult

  function runManual() {
    const wr = Number(manualWinPct) / 100
    const rr = Number(manualRR)
    if (!isFinite(wr) || !isFinite(rr) || rr <= 0) return
    setManualResult(
      runMonteCarlo({
        winRate: wr,
        avgRR: rr,
        trials: TRIALS,
        daysPerTrial: DAYS,
        startCapital: START_CAPITAL,
        riskPercent: RISK_PERCENT,
        targetCapital: TARGET_CAPITAL,
      }),
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Monte Carlo</CardTitle>
        <CardDescription>
          {auto
            ? `Auto · ${totalTrades} trades · WR ${(autoWinRate! * 100).toFixed(0)}% · RR médio ${autoAvgRR!.toFixed(2)}`
            : `Necessário 20+ trades para ativar análise automática (${totalTrades}/20). Use os inputs abaixo.`}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {!auto && (
          <div className="grid grid-cols-[1fr_1fr_auto] gap-2 items-end">
            <div className="space-y-1">
              <Label htmlFor="mc-wr" className="text-xs">Win rate (%)</Label>
              <Input
                id="mc-wr"
                inputMode="decimal"
                value={manualWinPct}
                onChange={(e) => setManualWinPct(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="mc-rr" className="text-xs">RR médio</Label>
              <Input
                id="mc-rr"
                inputMode="decimal"
                value={manualRR}
                onChange={(e) => setManualRR(e.target.value)}
              />
            </div>
            <Button type="button" onClick={runManual}>Rodar</Button>
          </div>
        )}

        {result ? (
          <>
            <div className="grid grid-cols-3 gap-3 text-sm">
              <Stat label={`P($${TARGET_CAPITAL} / 3x)`} value={`${(result.pHitTarget * 100).toFixed(1)}%`} accent="text-green-700 dark:text-green-400" />
              <Stat label="Mediana" value={`$${result.median.toFixed(0)}`} />
              <Stat label="P(perder >50%)" value={`${(result.pHalfDestroyed * 100).toFixed(1)}%`} accent="text-red-700 dark:text-red-400" />
            </div>

            <div className="h-56 w-full">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={result.histogram} margin={{ top: 8, right: 8, left: 0, bottom: 16 }}>
                  <XAxis
                    dataKey="label"
                    tick={{ fontSize: 10 }}
                    interval={3}
                    angle={-30}
                    textAnchor="end"
                    height={40}
                  />
                  <YAxis
                    tick={{ fontSize: 11 }}
                    width={28}
                    tickFormatter={(v: number) => `${(v * 100).toFixed(0)}%`}
                    dataKey="fraction"
                  />
                  <Tooltip
                    contentStyle={{ fontSize: 12, padding: '4px 8px' }}
                    formatter={(v) => [`${(Number(v) * 100).toFixed(2)}%`, 'Prob.']}
                    labelFormatter={(label) => `Final ~ ${label}`}
                  />
                  <ReferenceLine x={`$${START_CAPITAL}`} stroke="#9ca3af" strokeDasharray="2 2" />
                  <ReferenceLine x={`$${TARGET_CAPITAL}`} stroke={BAND_COLORS.target} strokeDasharray="2 2" />
                  <Bar dataKey="fraction">
                    {result.histogram.map((bin, i) => (
                      <Cell key={i} fill={bin.color} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>

            <div className="flex flex-wrap gap-3 text-[11px] text-muted-foreground">
              <Legend color={BAND_COLORS.destroyed} label="Destruição (≤50%)" />
              <Legend color={BAND_COLORS.belowStart} label="Abaixo do capital" />
              <Legend color={BAND_COLORS.profit} label="Lucro" />
              <Legend color={BAND_COLORS.target} label="Meta (3x)" />
            </div>
            <p className="text-[11px] text-muted-foreground">
              {TRIALS.toLocaleString('pt-BR')} simulações · {DAYS} dias · capital ${START_CAPITAL} · risco {(RISK_PERCENT * 100).toFixed(0)}%/trade
            </p>
          </>
        ) : (
          <p className="text-sm text-muted-foreground">Informe win rate e RR médio e clique em Rodar.</p>
        )}
      </CardContent>
    </Card>
  )
}

function Stat({ label, value, accent }: { label: string; value: string; accent?: string }) {
  return (
    <div className="rounded-md border p-2">
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className={`text-base font-semibold tabular-nums ${accent ?? ''}`}>{value}</p>
    </div>
  )
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className="inline-block w-2.5 h-2.5 rounded-sm" style={{ background: color }} />
      {label}
    </span>
  )
}
