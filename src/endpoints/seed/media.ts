import type { Payload } from 'payload'

import fs from 'fs'
import path from 'path'

export type MediaMap = Record<string, string>

interface SeedMediaFile {
  filename: string
  alt: string
}

const mediaFiles: SeedMediaFile[] = [
  { filename: 'avatar.png', alt: 'Prit Baldaniya profile photo' },
  { filename: 'hero.png', alt: 'Prit Baldaniya hero image' },
  { filename: 'project-challengerate.png', alt: 'ChallengeRate project screenshot' },
  { filename: 'project-drvandna.png', alt: 'Dr. Vandna website screenshot' },
  { filename: 'project-ecell.png', alt: 'E-Cell SVNIT website screenshot' },
  { filename: 'project-educave.png', alt: 'Educave platform screenshot' },
]

export async function seedMedia(payload: Payload): Promise<MediaMap> {
  const mediaMap: MediaMap = {}
  const seedDir = path.resolve(process.cwd(), 'public/seed')

  for (const { filename, alt } of mediaFiles) {
    const filePath = path.join(seedDir, filename)

    if (!fs.existsSync(filePath)) {
      payload.logger.warn(`Seed file not found: ${filePath}`)
      continue
    }

    const fileBuffer = fs.readFileSync(filePath)
    const mimeType = filename.endsWith('.png') ? 'image/png' : 'image/jpeg'

    const media = await payload.create({
      collection: 'media',
      data: {
        alt,
      },
      file: {
        data: fileBuffer,
        mimetype: mimeType,
        name: filename,
        size: fileBuffer.length,
      },
      context: {
        disableRevalidate: true,
      },
    })

    const key = filename.replace(/\.[^.]+$/, '')
    mediaMap[key] = media.id
    payload.logger.info(`Created media: ${alt} (${media.id})`)
  }

  return mediaMap
}
