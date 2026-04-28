'use client'

import { LineChart, Line, ReferenceLine, ResponsiveContainer, XAxis, YAxis, Tooltip } from 'recharts'

export type TrendPoint = { idx: number; r: number; date: string }

export function TrendChart({ data }: { data: TrendPoint[] }) {
  if (data.length === 0) {
    return <p className="text-muted-foreground text-sm">Sem trades para exibir.</p>
  }
  return (
    <div className="h-40 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
          <XAxis dataKey="idx" hide />
          <YAxis tick={{ fontSize: 11 }} width={28} />
          <ReferenceLine y={0} stroke="#9ca3af" strokeDasharray="3 3" />
          <Tooltip
            contentStyle={{ fontSize: 12, padding: '4px 8px' }}
            formatter={(v) => [`${Number(v).toFixed(2)}R`, 'R']}
            labelFormatter={(_, payload) => payload?.[0]?.payload?.date ?? ''}
          />
          <Line
            type="monotone"
            dataKey="r"
            stroke="#16a34a"
            strokeWidth={2}
            dot={{ r: 2 }}
            activeDot={{ r: 4 }}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
