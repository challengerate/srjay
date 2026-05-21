import { Suspense } from 'react'

import { getPayload } from 'payload'

import config from '@payload-config'
import { ContactSection } from '@/components/sections/ContactSection'
import { ExperienceSection } from '@/components/sections/ExperienceSection'
import { GitHubSection, GitHubContributionFallback } from '@/components/sections/GitHubSection'
import { HeroSection } from '@/components/sections/HeroSection'
import { OverviewSection } from '@/components/sections/OverviewSection'
import { ProjectsSection } from '@/components/sections/ProjectsSection'
import { TechStackSection } from '@/components/sections/TechStackSection'
import { getGitHubContributions } from '@/lib/github-contributions'
import { SectionLayout } from '@/components/Panel'
import { HomeScrollSpy } from '@/components/ScrollSpy/HomeScrollSpy'

const SECTIONS = [
  { id: 'hero', title: 'Overview' },
  { id: 'github', title: 'GitHub' },
  { id: 'stack', title: 'Stack' },
  { id: 'experience', title: 'Experience' },
  { id: 'projects', title: 'Projects' },
  { id: 'contact', title: 'Contact' },
]

export const dynamic = 'force-dynamic'

export default async function HomePage() {
  const payload = await getPayload({ config })

  // Fetch all data in parallel
  const [profile, projects, experiences, skills] = await Promise.all([
    payload.findGlobal({
      slug: 'profile',
      depth: 2,
    }),
    payload.find({
      collection: 'projects',
      sort: '-order',
      depth: 2,
      limit: 10,
    }),
    payload.find({
      collection: 'experiences',
      sort: '-order',
      depth: 2,
      limit: 20,
    }),
    payload.find({
      collection: 'skills',
      where: { showOnStack: { equals: true } },
      sort: '-order',
      depth: 1,
      limit: 20,
    }),
  ])

  const githubUsername = profile.github || 'srjaykikani'
  const contributions = getGitHubContributions(githubUsername)

  return (
    <>
      {/* Fixed ScrollSpy - Hidden on mobile/tablet */}
      <HomeScrollSpy sections={SECTIONS} />

      <main className="max-w-screen overflow-x-hidden px-4 sm:px-6 py-4">
        <div className="mx-auto max-w-2xl flex flex-col">
          <HeroSection profile={profile} />
          <OverviewSection profile={profile} />
          <SectionLayout title="GitHub" className="scroll-mt-12" id="github">
            <Suspense fallback={<GitHubContributionFallback />}>
              <GitHubSection username={githubUsername} contributions={contributions} />
            </Suspense>
          </SectionLayout>
          <TechStackSection skills={skills.docs} />
          <ExperienceSection experiences={experiences.docs} />
          <ProjectsSection projects={projects.docs} />
          <ContactSection profile={profile} />
        </div>
      </main>
    </>
  )
}
