import { PrismaClient } from '@prisma/client'
import { PrismaNeon } from '@prisma/adapter-neon'
import { neonConfig } from '@neondatabase/serverless'
import ws from 'ws'

neonConfig.webSocketConstructor = ws

const adapter = new PrismaNeon({ connectionString: process.env.DATABASE_URL })
const prisma = new PrismaClient({ adapter })

const patterns = [
  {
    name: 'MTR (Major Trend Reversal)',
    description: 'Reversão maior de tendência — dois empurrões na direção da tendência, seguido de rompimento da linha de tendência e pullback.',
  },
  {
    name: 'Failed Breakout',
    description: 'Rompimento que falha: o preço rompe um nível, não consegue sustentar e reverte, armadilhando os latecomers.',
  },
  {
    name: 'Breakout Pullback',
    description: 'Após um rompimento legítimo de resistência ou suporte, o preço recua para testar o nível rompido antes de continuar.',
  },
  {
    name: 'Double Top',
    description: 'Dois topos no mesmo nível com volume decrescente; sinal de fraqueza dos compradores e possível reversão baixista.',
  },
  {
    name: 'Double Bottom',
    description: 'Dois fundos no mesmo nível; sinal de força dos compradores e possível reversão altista.',
  },
  {
    name: 'Wedge',
    description: 'Canal convergente (cunha) altista ou baixista; normalmente resulta em rompimento na direção oposta à cunha.',
  },
  {
    name: 'Channel Pullback',
    description: 'Recuo para a média ou linha inferior/superior do canal dentro de uma tendência estabelecida.',
  },
  {
    name: 'Triangle Breakout',
    description: 'Rompimento de triângulo simétrico, ascendente ou descendente após compressão de volatilidade.',
  },
  {
    name: 'Inside Bar (ii)',
    description: 'Uma ou mais barras internas (inside bars) — range completamente dentro da barra anterior; indica compressão e potencial expansão.',
  },
  {
    name: 'Spike and Channel',
    description: 'Movimento vertical agressivo (spike) seguido de canal em ângulo menor na mesma direção; frequentemente termina com reversão.',
  },
  {
    name: 'Trading Range Breakout',
    description: 'Rompimento de uma faixa de consolidação horizontal com follow-through na direção do rompimento.',
  },
]

async function main() {
  console.log('Seeding patterns...')
  for (const pattern of patterns) {
    await prisma.pattern.upsert({
      where: { name: pattern.name },
      update: { description: pattern.description },
      create: pattern,
    })
  }
  console.log(`${patterns.length} patterns seeded.`)
}

main()
  .catch((e) => {
    console.error(e)
    process.exit(1)
  })
  .finally(() => prisma.$disconnect())
