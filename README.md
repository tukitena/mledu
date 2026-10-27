# MLedu

Hệ thống quản lý trung tâm dạy thêm Miss Lien Edu: Vue SPA (Cloudflare Pages) → API
Hono (Cloudflare Workers) → Supabase (Auth, PostgreSQL/RPC, Storage, Realtime, Cron).

- Đặc tả nghiệp vụ: [docs/developer/plans.md](docs/developer/plans.md)
- Tech stack: [docs/developer/techstack.md](docs/developer/techstack.md)
- Lộ trình: [docs/developer/Implementation-plan.md](docs/developer/Implementation-plan.md)
- Quyết định kỹ thuật: [docs/developer/decisions/](docs/developer/decisions/)

Trạng thái: **GĐ 2 — tài khoản, phiên, hồ sơ và avatar** (local,
[biên bản](docs/developer/decisions/gd2-auth-profile.md)). Chưa có dữ liệu thật hoặc deploy.

## Cấu trúc

```text
apps/web            Vue SPA (Vite) — chỉ gọi API Worker
apps/api            Worker Hono — /v1/*, kiểm tra phiên/quyền tại request
packages/contracts  DTO/schema dùng chung (zod), không chứa secret
supabase/           config local, migrations, seeds local, tests/database (pgTAP)
tests/fixtures      Dữ liệu giả riêng cho CI/test, có trên Git
tests/e2e           Playwright
scripts/dev         Công cụ phát triển
scripts/testing     Dựng và kiểm tra stack Supabase riêng cho test
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

`local:env` ghi `apps/api/.dev.vars` (gồm secret key, chỉ cho Worker) và
`apps/web/.env.local` (chỉ giá trị công khai), đều bị Git bỏ qua, từ `supabase status`.
Sau khi đổi `supabase/config.toml` (hook, template email) cần `supabase stop` rồi `supabase start`.
Email đặt lại mật khẩu local xem tại Mailpit http://127.0.0.1:54324. Sau đó chạy API (cổng 8787) và web (cổng 5173) ở hai terminal:

```bash
npm run dev:api
```

```bash
npm run dev:web
```

Stack mở app là **mledu-dev**, cổng Supabase 54321/54322. Seed hiện chỉ có
`supabase/seeds/00-account.sql`; không có danh mục, học sinh hay lớp fixture.
Tài khoản tạm trong file này (chỉ Auth local): `admin@`,
`receptionist@`, `user@`, `pending@` (phải đổi mật khẩu), `disabled@` (bị khóa) thuộc
`example.com`, mật khẩu `123456ab`.

`supabase/seeds/` dùng cho dữ liệu local và dữ liệu nội bộ cần nạp khi triển khai;
không tạo thư mục `internal`. Các file mới tại đây bị Git ignore. Riêng `00-account.sql`
tạm được theo dõi theo yêu cầu hiện tại. **Trước khi thay bằng tài khoản thật**, bỏ dòng
ngoại lệ trong `.gitignore` và chạy `git rm --cached supabase/seeds/00-account.sql`:
chỉ thêm ignore không làm Git ngừng theo dõi file đã commit.

Các file được nạp theo thứ tự tên khi khởi tạo/reset local. Mở lại stack không tự nạp lại.
Deploy code/schema và nạp dữ liệu nội bộ là các bước riêng: seed riêng được cung cấp từ
máy triển khai tin cậy, không qua CI/artifacts. Không đưa các tài khoản tạm này lên hosted.
Tài khoản thật dùng công cụ vận hành bên dưới; dữ liệu nghiệp vụ cần giữ validation/audit.

## Môi trường kiểm thử riêng

```bash
npm run test:stack:start
npm run test:db
npm run test:db:concurrency
npm run test:integration
npm run test:e2e
```

Stack **mledu-test** dùng cổng 55321/55322, Mailpit 55324, cùng nguồn migrations nhưng
Auth/Storage/volume riêng. `test:stack:start` sinh cấu hình trong `tmp/supabase-test/`
và chỉ sao chép `tests/fixtures/database/`; không đọc `supabase/seeds/`, không sửa
`.dev.vars` hoặc `.env.local` của app. Bản tài khoản fixture độc lập với seed local.
Integration, E2E, kiểm thử đồng thời và cấu hình Auth spike không fallback sang DB dev.
Unit tests không cần stack và không đọc secret local.

`npm run test:stack:reset` dựng lại **chỉ DB test**; `npm run test:stack:stop` dừng stack,
giữ volume. Sau khi đổi migrations/fixture, chạy reset để áp dụng lại. Cấu hình và credential
test sinh ra đều bị Git ignore, không đưa vào build/deploy. CI dùng cùng lệnh và không có
thư mục seed local khi chạy database tests.

Khi chuyển từ cấu hình cũ `mledu`: dừng stack cũ bằng `supabase stop --project-id mledu`
(giữ volume), rồi chạy `npm run db:start` và `npm run local:env`. Stack `mledu-dev` mới chỉ
nạp seed local. Không reset/xóa DB cũ để dọn fixture; dữ liệu cũ giữ lại để đối chiếu/chuyển
những bản ghi cần thiết. Đổi đường dẫn seed không tự xóa dữ liệu đã có trong DB cũ.

## Lệnh kiểm chứng

| Lệnh | Nội dung |
| --- | --- |
| `npm run lint` / `npm run format:check` | ESLint / Prettier |
| `npm run typecheck` | Công cụ test, contracts, API (workerd + Node config), web (`vue-tsc`) |
| `npm run test:unit` | Vitest; test API chạy trong runtime Workers |
| `npm run test:tooling` | Chặn kết nối dev/remote, kiểm tra fixture không đọc seed riêng |
| `npm run test:db` | pgTAP trên mledu-test |
| `npm run test:db:concurrency` | Hai kết nối PostgreSQL của mledu-test |
| `npm run test:integration` | Worker + mledu-test (cần `test:stack:start`) |
| `npm run test:e2e` | Playwright; Worker 8797 và web 5183 cùng dùng mledu-test |
| `npm run build` | `apps/web/dist` và bundle Worker `apps/api/dist` |
| `npm run check:artifacts` | Chặn secret và đường dẫn `template/` trong bản build |
| `npm run db:reset` / `npm run db:types` | Dựng lại DB local / sinh lại kiểu `api` |
| `npm run test:db:types` | Sinh kiểu từ mledu-test, dùng trong CI |

Tài khoản Admin chỉ được quản trị bằng công cụ vận hành (AUTH-06), không qua ứng dụng:
`node scripts/ops/accounts.mjs create|temp-password|set …` với `SUPABASE_URL`,
`SUPABASE_SECRET_KEY`, `MLEDU_OPERATOR` lấy từ môi trường (xem đầu file).

Mã thử nghiệm Auth GĐ 0 (chỉ local): `npm run spike:db`, `npm run dev:auth-spike`,
`npm run test:auth:integration` — điều kiện chạy ghi trong `supabase/spike/gd0-auth-spike.sql`.

Không trỏ test tự động hoặc `db reset` vào staging/production. Deploy staging thủ công:
`npm run deploy:staging -w @mledu/api` sau khi đặt secret bằng `wrangler secret put`.
