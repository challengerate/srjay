import type { Metadata } from 'next'

import { getPayload } from 'payload'

import config from '@payload-config'
import { MasonryGrid } from '@/components/Gallery/MasonryGrid'

export const metadata: Metadata = {
  title: 'Gallery',
  description: 'A curated collection of photos and visual moments.',
}

export const dynamic = 'force-dynamic'

export default async function GalleryPage() {
  const payload = await getPayload({ config })

  const gallery = await payload.find({
    collection: 'gallery',
    sort: '-order',
    depth: 1,
    limit: 100,
  })

  return (
    <main className="max-w-screen overflow-x-hidden px-4 sm:px-6 py-4">
      <div className="mx-auto max-w-2xl py-12">
        <h1 className="text-4xl font-bold tracking-tight text-foreground mb-10">Gallery</h1>
        <MasonryGrid items={gallery.docs} columns={2} />
      </div>
    </main>
  )
}
