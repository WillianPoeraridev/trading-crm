import type { Metadata } from "next";
import { Geist } from "next/font/google";
import Link from "next/link";
import "./globals.css";

const geist = Geist({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Trading CRM",
  description: "CRM pessoal de trading",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="pt-BR" className={`${geist.className} h-full antialiased`}>
      <body className="min-h-full flex flex-col bg-background text-foreground">
        <header className="border-b px-6 py-3 flex items-center gap-6">
          <span className="font-semibold text-sm">Trading CRM</span>
          <nav className="flex gap-4 text-sm">
            <Link href="/" className="hover:underline">Dashboard</Link>
            <Link href="/trades" className="hover:underline">Trades</Link>
          </nav>
        </header>
        <main className="flex-1 p-6">{children}</main>
      </body>
    </html>
  );
}
