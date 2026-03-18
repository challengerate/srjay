import type { Payload, RequiredDataFromCollectionSlug } from 'payload'

import type { MediaMap } from './media'

// Rich text helpers
function text(content: string, format: 0 | 1 | 2 = 0) {
  return {
    type: 'text' as const,
    detail: 0,
    format,
    mode: 'normal' as const,
    style: '',
    text: content,
    version: 1 as const,
  }
}

function paragraph(...children: ReturnType<typeof text>[]) {
  return {
    type: 'paragraph' as const,
    children,
    direction: 'ltr' as const,
    format: '' as const,
    indent: 0,
    textFormat: 0,
    version: 1 as const,
  }
}

function richText(...nodes: ReturnType<typeof paragraph>[]) {
  return {
    root: {
      type: 'root' as const,
      children: nodes,
      direction: 'ltr' as const,
      format: '' as const,
      indent: 0,
      version: 1 as const,
    },
  }
}

type ProfileData = {
  name: string
  title: string
  bio: RequiredDataFromCollectionSlug<'projects'>['content']
  avatar?: string
  email: string
  phone?: string
  location?: string
  timezone?: string
  github?: string
  languages?: { language: string }[]
  socialLinks?: {
    platform: 'github' | 'twitter' | 'instagram' | 'linkedin'
    url: string
    label?: string
  }[]
}

export function getProfileData(mediaMap: MediaMap): ProfileData {
  return {
    name: "Hey, I'm Prit!",
    title: 'Software Developer',
    languages: [{ language: 'English' }, { language: 'Hindi' }, { language: 'Gujarati' }],
    bio: richText(
      paragraph(
        text(
          'I ship fast and keep things simple—so what I build stays clear, reliable, and easy to run as it grows.',
        ),
      ),
      paragraph(text("That's the bar: systems people trust, without unnecessary complexity.")),
      paragraph(
        text('Since December 2023, '),
        text('Payload', 1),
        text(
          " has been my go-to CMS; it's a core part of how I build flexible, production-ready platforms.",
        ),
      ),
    ),
    avatar: mediaMap['avatar'],
    email: 'hello@example.com',
    phone: '+1 (555) 123-4567',
    location: 'Gujarat, India',
    timezone: 'Asia/Kolkata',
    github: 'prit007p',
    socialLinks: [
      {
        platform: 'github',
        url: 'https://github.com/prit007p',
        label: 'GitHub',
      },
      {
        platform: 'twitter',
        url: 'https://twitter.com/prit007p',
        label: 'Twitter / X',
      },
      {
        platform: 'instagram',
        url: 'https://instagram.com/prit_baldaniya_',
        label: 'Instagram',
      },
      {
        platform: 'linkedin',
        url: 'https://www.linkedin.com/in/prit-baldaniya-98b221272/',
        label: 'LinkedIn',
      },
    ],
  }
}

export async function seedProfile(payload: Payload, mediaMap: MediaMap): Promise<void> {
  const profileData = getProfileData(mediaMap)

  await payload.updateGlobal({
    slug: 'profile',
    data: profileData,
    context: {
      disableRevalidate: true,
    },
  })

  payload.logger.info('Profile global updated')
}
