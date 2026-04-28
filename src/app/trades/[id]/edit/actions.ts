'use server'

import { redirect } from 'next/navigation'
import { prisma } from '@/lib/prisma'

export async function updateTrade(id: string, formData: FormData) {
  const notes = (formData.get('notes') as string) || null
  const screenshotUrl = (formData.get('screenshotUrl') as string) || null

  await prisma.trade.update({
    where: { id },
    data: { notes, screenshotUrl },
  })

  redirect(`/trades/${id}`)
}
