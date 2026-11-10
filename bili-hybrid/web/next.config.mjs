/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // PYTHON_API_ORIGIN 只在服务端可见。刻意不加 NEXT_PUBLIC_ 前缀：
  // 浏览器一律访问同源 /api/*，FastAPI 的地址/端口不下发到客户端。
};

export default nextConfig;
