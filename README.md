# MLedu

Hệ thống quản lý trung tâm dạy thêm Miss Lien Edu: Vue SPA (Cloudflare Pages) → API
Hono (Cloudflare Workers) → Supabase (Auth, PostgreSQL/RPC, Storage, Realtime, Cron).

- Đặc tả nghiệp vụ: [docs/developer/plans.md](docs/developer/plans.md)
- Tech stack: [docs/developer/techstack.md](docs/developer/techstack.md)
- Lộ trình: [docs/developer/Implementation-plan.md](docs/developer/Implementation-plan.md)
- Quyết định kỹ thuật: [docs/developer/decisions/](docs/developer/decisions/)

Trạng thái: **GĐ 1 — nền dự án** ([biên bản](docs/developer/decisions/gd1-foundation.md)).
Chưa có chức năng nghiệp vụ hoặc dữ liệu thật.

## Cấu trúc

```text
apps/web            Vue SPA (Vite) — chỉ gọi API Worker
apps/api            Worker Hono — /v1/*, kiểm tra phiên/quyền tại request
packages/contracts  DTO/schema dùng chung (zod), không chứa secret
supabase/           config, migrations, seed (dữ liệu giả), tests/database (pgTAP)
tests/e2e           Playwright
scripts/dev         Công cụ phát triển
```

`template/` (giao diện tham khảo) và `.agents/` bị Git bỏ qua; không import hoặc dùng
khi build.

## Chạy local

Yêu cầu: Node 24.12 (`.nvmrc`), Docker, Supabase CLI 2.120+.

```bash
npm install
```

```bash
supabase start
```

```bash
npm run local:env
```

`local:env` ghi `apps/api/.dev.vars` và `apps/web/.env.local` (đều bị Git bỏ qua) từ
`supabase status`. Sau đó chạy API (cổng 8787) và web (cổng 5173) ở hai terminal:

```bash
npm run dev:api
```

```bash
npm run dev:web
```

Tài khoản giả trong `supabase/seed.sql` (chỉ Auth local): `admin@`, `receptionist@`,
`user@`, `pending@` (phải đổi mật khẩu), `disabled@` (bị khóa) thuộc `mledu.test`,
mật khẩu `mledu-local-only`.

## Lệnh kiểm chứng

| Lệnh | Nội dung |
| --- | --- |
| `npm run lint` / `npm run format:check` | ESLint / Prettier |
| `npm run typecheck` | contracts, API (workerd + Node config), web (`vue-tsc`) |
| `npm run test:unit` | Vitest; test API chạy trong runtime Workers |
| `npm run test:db` | pgTAP trên Supabase local (`supabase test db`) |
| `npm run test:integration` | Worker + Supabase local thật (cần `local:env`) |
| `npm run test:e2e` | Playwright; tự chạy Worker 8797 và web 5183 |
| `npm run build` | `apps/web/dist` và bundle Worker `apps/api/dist` |
| `npm run check:artifacts` | Chặn secret và đường dẫn `template/` trong bản build |
| `npm run db:reset` / `npm run db:types` | Dựng lại DB local / sinh lại kiểu `api` |

Mã thử nghiệm Auth GĐ 0 (chỉ local): `npm run spike:db`, `npm run dev:auth-spike`,
`npm run test:auth:integration` — điều kiện chạy ghi trong `supabase/spike/gd0-auth-spike.sql`.

Không trỏ test tự động hoặc `db reset` vào staging/production. Deploy staging thủ công:
`npm run deploy:staging -w @mledu/api` sau khi đặt secret bằng `wrangler secret put`.
