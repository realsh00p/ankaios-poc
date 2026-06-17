import './globals.css';
import React from 'react';

const navItems = [
  ['Home', '/'],
  ['Targets', '/targets'],
  ['SolutionVersions', '/solutions'],
  ['Instances', '/instances'],
  ['Campaigns', '/campaigns'],
  ['Catalogs', '/catalogs'],
  ['Assets', '/assets'],
  ['Sites', '/sites'],
];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <header style={{ background: '#111827', color: 'white', padding: '12px 18px' }}>
          <div style={{ fontSize: 18, fontWeight: 700, marginBottom: 10 }}>Symphony Opera</div>
          <nav style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
            {navItems.map(([label, href]) => (
              <a key={href} href={href} style={{ color: 'white', textDecoration: 'none' }}>{label}</a>
            ))}
          </nav>
        </header>
        <main style={{ padding: 18 }}>{children}</main>
      </body>
    </html>
  );
}
