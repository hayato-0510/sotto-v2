import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /**
   * Next.js 16 の開発サーバーは、既定で localhost 以外の Origin からの
   * /_next/* 等へのリクエストを 403 で拒否する（allowedDevOrigins）。
   * 旧リポジトリ（sotto）でスマホ実機確認ができない原因になった
   * （docs/POSTMORTEM.md 参照）。開発中のスマホ実機確認のためだけの設定。
   * Wi-Fi環境が変わってIPが変わったら、ここを更新すること
   * （`ipconfig` の IPv4 アドレスを確認）。
   */
  allowedDevOrigins: ["192.168.11.11"],
};

export default nextConfig;
