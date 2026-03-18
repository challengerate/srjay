# pritbaldaniya.com

Personal portfolio website built with Next.js, Payload CMS, and tRPC.

## Tech Stack

| Component     | Technology                    |
| ------------- | ----------------------------- |
| Framework     | Next.js 15 (App Router)       |
| Language      | TypeScript (strict)           |
| Database      | MongoDB                       |
| CMS           | Payload CMS 3                 |
| API           | tRPC v11                      |
| Data Fetching | TanStack React Query          |
| Storage       | Cloudflare R2 (S3-compatible) |
| Styling       | Tailwind CSS v4               |

## Getting Started

1. Install dependencies:

   ```bash
   pnpm install
   ```

2. Create a `.env` file:

   ```bash
   cp .env.example .env
   ```

3. Set up environment variables in `.env`

4. Start the development server:

   ```bash
   pnpm dev
   ```

5. Open http://localhost:3000

## Commands

```bash
pnpm dev              # Start dev server (port 3000)
pnpm build            # Build for production
pnpm start            # Start production server
pnpm check-types      # Type check
pnpm lint             # Lint
pnpm test             # Run tests
pnpm generate:types   # Regenerate types after schema changes
```

## Project Structure

```
src/
├── app/                 # Next.js App Router
│   ├── (frontend)/      # Public routes
│   ├── (payload)/       # Payload Admin
│   └── api/trpc/        # tRPC endpoint
├── components/          # React components
├── lib/                 # UI utilities (cn, type guards)
├── payload/             # Payload CMS config
├── trpc/                # tRPC setup
└── utilities/           # App helpers (URL, SEO, globals)
```

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## License

MIT - Feel free to use this code for your own portfolio.
