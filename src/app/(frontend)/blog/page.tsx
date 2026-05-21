import { getPayload } from 'payload'

import type { Metadata } from 'next'

import config from '@payload-config'
import { BlogCard, BlogGrid } from '@/components/Blog/BlogCard'

export const metadata: Metadata = {
  title: 'Blog',
  description: 'Thoughts on development, design, and technology.',
}

export const dynamic = 'force-dynamic'

export default async function BlogPage() {
  const payload = await getPayload({ config })

  const { docs: blogs } = await payload.find({
    collection: 'blogs',
    sort: '-publishedAt',
    depth: 1,
    limit: 100,
  })

  // Split blogs: first one featured, rest in grid
  const [featuredBlog, ...remainingBlogs] = blogs
  const recentBlogs = remainingBlogs.slice(0, 4)
  const olderBlogs = remainingBlogs.slice(4)

  return (
    <main className="max-w-screen overflow-x-hidden px-4 sm:px-6 py-4">
      <div className="mx-auto max-w-2xl py-12">
        <h1 className="text-4xl font-bold tracking-tight text-foreground mb-10">Blog</h1>

        {featuredBlog && (
          <div className="mb-12">
            <BlogCard blog={featuredBlog} featured />
          </div>
        )}

        {recentBlogs.length > 0 && (
          <div className="mb-12">
            <BlogGrid blogs={recentBlogs} columns={2} />
          </div>
        )}

        {olderBlogs.length > 0 && (
          <>
            <h2 className="text-2xl font-semibold text-foreground mb-8">Earlier Posts</h2>
            <BlogGrid blogs={olderBlogs} columns={2} />
          </>
        )}

        {blogs.length === 0 && (
          <p className="text-muted-foreground text-center py-12">No blog posts yet.</p>
        )}
      </div>
    </main>
  )
}
