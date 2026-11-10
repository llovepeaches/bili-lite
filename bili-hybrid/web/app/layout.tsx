import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  title: "Bili Hybrid · Rust + Python + Next.js",
  description: "混合架构示例：Rust 计算内核 / PyO3 精简 Python 包 / FastAPI / Next.js BFF",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
