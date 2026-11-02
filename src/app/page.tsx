import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

/**
 * Temporary setup-check page for Phase 1.
 * The real landing page is built in the public-pages phase.
 */
export default function HomePage() {
  return (
    <main className="mx-auto flex min-h-dvh max-w-2xl flex-col justify-center gap-6 px-4 py-16">
      <div className="space-y-2">
        <p className="text-sm font-medium text-muted-foreground">Phase 1 · Project setup</p>
        <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">BookFlow</h1>
        <p className="text-muted-foreground">Smart appointment booking and management.</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Setup check</CardTitle>
          <CardDescription>
            If this page renders with styled components, Next.js, Tailwind and shadcn/ui are working.
            Open the health check to confirm the Supabase connection.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-3">
          <a href="/api/health" className={buttonVariants()}>
            Open /api/health
          </a>
          <Link href="/dashboard" className={buttonVariants({ variant: "outline" })}>
            Try a protected route
          </Link>
        </CardContent>
      </Card>
    </main>
  );
}
