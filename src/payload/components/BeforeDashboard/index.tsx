import React from 'react'
import { SeedButton } from './SeedButton'

export const BeforeDashboard: React.FC = () => {
  return (
    <div
      style={{
        padding: '24px',
        backgroundColor: '#F8F9FA',
        borderRadius: '12px',
        marginBottom: '24px',
      }}
    >
      <h2 style={{ marginTop: 0, marginBottom: '8px', fontSize: '18px' }}>
        Welcome to pritbaldaniya.com CMS
      </h2>
      <p style={{ marginBottom: '16px', color: '#5F6368' }}>
        Click the button below to seed your database with sample content.
      </p>
      <SeedButton />
    </div>
  )
}
