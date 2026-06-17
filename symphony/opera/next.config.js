/** @type {import('next').NextConfig} */
const nextConfig = {
    output: 'standalone',
    images: {
        domains: ['static.boredpanda.com', 'avatars.githubusercontent.com'],
    },
    experimental: {
        serverActions: true,
    },
}

module.exports = nextConfig
