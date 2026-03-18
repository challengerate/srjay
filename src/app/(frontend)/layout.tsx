import type { Metadata } from 'next'

import React from 'react'
import { SpeedInsights } from '@vercel/speed-insights/next'
import { Analytics } from '@vercel/analytics/next'

import { TRPCReactProvider } from '@/trpc/client'
import { Providers } from '@/providers'
import { Header } from '@/components/Header/Component'
import { Footer } from '@/components/Footer/Component'
import { InitTheme } from '@/providers/Theme/InitTheme'
import { mergeOpenGraph } from '@/utilities/mergeOpenGraph'
import { getServerSideURL } from '@/utilities/getURL'

import './styles.css'

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <InitTheme />
        <link href="/favicon.ico" rel="icon" sizes="32x32" />
        <link href="/favicon.svg" rel="icon" type="image/svg+xml" />
      </head>
      <body className="antialiased">
        <TRPCReactProvider>
          <Providers>
            <Header />
            <main className="flex-grow">{children}</main>
            <Footer />
          </Providers>
        </TRPCReactProvider>
        <SpeedInsights />
        <Analytics />
      </body>
    </html>
  )
}

export const metadata: Metadata = {
  metadataBase: new URL(getServerSideURL()),
  title: {
    default: 'Prit Baldaniya | Full-Stack Developer',
    template: '%s | Prit Baldaniya',
  },
  description:
    'Prit Baldaniya - Full-stack developer specializing in Next.js, Payload CMS, React, and TypeScript. Building scalable web applications with modern technologies.',
  keywords: [
    'Prit Baldaniya',
    'Full-Stack Developer',
    'Next.js Developer',
    'Payload CMS',
    'React Developer',
    'TypeScript',
    'Web Development',
    'tRPC',
    'TanStack Query',
    'Software Engineer',
    'ChallengeRate',
  ],
  authors: [{ name: 'Prit Baldaniya', url: 'https://pritbaldaniya.com' }],
  creator: 'Prit Baldaniya',
  publisher: 'Prit Baldaniya',
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-video-preview': -1,
      'max-image-preview': 'large',
      'max-snippet': -1,
    },
  },
  openGraph: mergeOpenGraph(),
  twitter: {
    card: 'summary_large_image',
    creator: '@_pritbaldaniya',
    site: '@_pritbaldaniya',
    title: 'Prit Baldaniya | Full-Stack Developer',
    description:
      'Full-stack developer specializing in Next.js, Payload CMS, React, and TypeScript. Building scalable web applications.',
  },
}
