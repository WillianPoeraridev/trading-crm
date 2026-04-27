import { getPatterns } from '../actions'
import { TradeForm } from './TradeForm'

export const dynamic = 'force-dynamic'

export default async function NewTradePage() {
  const patterns = await getPatterns()
  return (
    <div className="max-w-2xl mx-auto space-y-4">
      <h1 className="text-2xl font-bold">Novo Trade</h1>
      <TradeForm patterns={patterns} />
    </div>
  )
}
