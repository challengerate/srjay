import type { Metadata } from 'next'

import { getServerSideURL } from './getURL'

const defaultOpenGraph: Metadata['openGraph'] = {
  type: 'website',
  locale: 'en_US',
  url: getServerSideURL(),
  siteName: 'Prit Baldaniya',
  title: 'Prit Baldaniya | Full-Stack Developer',
  description:
    'Prit Baldaniya - Full-stack developer specializing in Next.js, Payload CMS, React, and TypeScript. Building scalable web applications with modern technologies.',
  images: [
    {
      url: `${getServerSideURL()}/og-image.png`,
      width: 1200,
      height: 630,
      alt: 'Prit Baldaniya - Full-Stack Developer',
    },
  ],
}

export const mergeOpenGraph = (og?: Metadata['openGraph']): Metadata['openGraph'] => {
  return {
    ...defaultOpenGraph,
    ...og,
    images: og?.images ? og.images : defaultOpenGraph.images,
  }
}
