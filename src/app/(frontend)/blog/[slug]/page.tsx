import Image from 'next/image'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { getPayload } from 'payload'
import { ArrowLeft } from 'lucide-react'

import type { Metadata } from 'next'
import type { Blog } from '@/payload-types'

import config from '@payload-config'
import { RichText } from '@/components/RichText'
import { TableOfContents } from '@/components/TableOfContents'
import { getMedia } from '@/lib/type-guards'

export const dynamic = 'force-dynamic'

interface PageProps {
  params: Promise<{ slug: string }>
}

function formatDate(dateString: string): string {
  const date = new Date(dateString)
  return date.toLocaleDateString('en-US', {
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  })
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { slug } = await params
  const payload = await getPayload({ config })

  const { docs } = await payload.find({
    collection: 'blogs',
    where: { slug: { equals: slug } },
    depth: 0,
    limit: 1,
  })

  const blog = docs[0]
  if (!blog) return {}

  return {
    title: blog.meta?.title || blog.title,
    description: blog.meta?.description || blog.summary,
  }
}

export default async function BlogPostPage({ params }: PageProps) {
  const { slug } = await params
  const payload = await getPayload({ config })

  const { docs } = await payload.find({
    collection: 'blogs',
    where: { slug: { equals: slug } },
    depth: 2,
    limit: 1,
  })

  const blog = docs[0] as Blog | undefined
  if (!blog) notFound()

  const image = getMedia(blog.image)

  return (
    <main className="max-w-screen overflow-x-hidden px-4 sm:px-6 py-4">
      <div className="mx-auto max-w-6xl flex gap-8 py-12">
        {/* Left spacer for balance */}
        <div className="hidden lg:block w-48 shrink-0" />

        {/* Main Content */}
        <article className="flex-1 max-w-2xl mx-auto">
          {/* Header */}
          <div className="flex flex-col gap-4 mb-8">
            <Link
              href="/blog"
              className="inline-flex items-center text-sm text-muted-foreground hover:text-foreground transition-colors"
            >
              <ArrowLeft className="w-4 h-4 mr-1" />
              Back to blog
            </Link>
            <p className="text-sm text-muted-foreground">{formatDate(blog.publishedAt)}</p>
            <h1 className="text-4xl sm:text-5xl font-bold tracking-tight text-foreground">
              {blog.title}
            </h1>
            {blog.summary && (
              <p className="text-lg text-muted-foreground leading-relaxed">{blog.summary}</p>
            )}
          </div>

          {/* Cover Image */}
          {image?.url && (
            <div className="relative aspect-video rounded-xl overflow-hidden border border-border bg-muted mb-8">
              <Image
                src={image.url}
                alt={image.alt || `${blog.title} cover`}
                fill
                className="object-cover"
                priority
                sizes="(max-width: 768px) 100vw, (max-width: 1200px) 80vw, 768px"
              />
            </div>
          )}

          {/* Content */}
          {blog.content && (
            <div className="prose prose-neutral dark:prose-invert max-w-none leading-relaxed">
              <RichText data={blog.content} />
            </div>
          )}
        </article>

        {/* Right side - Table of Contents */}
        <aside className="hidden lg:block w-48 shrink-0">
          <div className="sticky top-20">
            <TableOfContents />
          </div>
        </aside>
      </div>
    </main>
  )
}
