# GĐ 1 — Nền dự án, môi trường và kiểm thử

Ngày: **26/10/2026**, múi giờ Asia/Ho_Chi_Minh.

**Trạng thái: hoàn thành các hạng mục nền của GĐ 1 trên môi trường local.** CI đã
được viết nhưng **chưa chạy trên GitHub** vì repository chưa có remote. Chưa deploy
staging/production. Các mục chuyển tiếp G1-01–05 của [GĐ 0](gd0-closeout.md) vẫn
mở và không được coi là đạt nhờ các test bên dưới.

## Phiên bản đã chốt

Chọn bản mới nhất tương thích lẫn nhau tại ngày ghi nhận; không lấy phiên bản từ template.

| Thành phần | Phiên bản | Ghi chú |
| --- | --- | --- |
| Node.js / npm | 24.12.0 (`.nvmrc`) / 11.19.0 | `engines` `>=24.12.0 <25` |
| TypeScript | 6.0.3 | `typescript-eslint` 8.72 chỉ hỗ trợ TS `<6.1`; chưa dùng TS 7 |
| Vue / Vue Router / Vite | 3.5.44 / 5.4.0 / 8.3.5 | `vue-tsc` 3.3.13, `@vitejs/plugin-vue` 6.0.10 |
| Bootstrap / Icons / Sass | 5.3.8 / 1.13.2 / 1.106.1 | Tắt cảnh báo `@import` của Bootstrap 5.3 trong Vite |
| Hono / Wrangler | 4.13.14 / 4.153.0 | `compatibility_date` 2026-10-01 |
| Vitest / Workers test | 5.0.5 / `@cloudflare/vitest-plugin` 1.4.8 | `@cloudflare/vitest-pool-workers` đã đổi tên và kéo theo phụ thuộc có lỗ hổng; không dùng |
| supabase-js / Supabase CLI | 2.118.0 / 2.120.0 | CI cố định CLI 2.120.0 như máy local |
| zod | 4.6.7 | Schema hợp đồng trong `packages/contracts` |
| Playwright | 1.64.1 | Chromium desktop + Pixel 7 |

`npm audit`: 0 lỗ hổng tại thời điểm cài.

### Dependency cài sẵn cho các giai đoạn sau (27/10/2026)

Đã cài và khóa phiên bản chính xác nhưng **chưa dùng trong mã**; bundle không chứa
chúng cho tới khi được import. Phiên bản/wrapper vẫn phải qua kiểm tra tích hợp khi
giai đoạn tương ứng bắt đầu (techstack §3).

| Gói (`apps/web`) | Phiên bản | Giai đoạn | Ghi chú |
| --- | --- | --- | --- |
| `vue-i18n` | 11.4.16 | GĐ 2 (UX-01) | Việt/Anh |
| `@supabase/supabase-js` | 2.118.0 | GĐ 2, 9 | Auth SDK và Realtime ở trình duyệt; nghiệp vụ vẫn qua Worker |
| `@fullcalendar/vue3` + `temporal-polyfill` | 7.1.3 + 1.0.6 | GĐ 4 | FullCalendar v7: plugin dayGrid/timeGrid/interaction lấy từ subpath `@fullcalendar/vue3/*`; không cài các gói `@fullcalendar/*` v6 |
| `tabulator-tables` (+ `@types/tabulator-tables` 6.3.6) | 6.7.1 | GĐ 3+ | Bảng phức tạp |
| `tom-select` | 2.6.2 | GĐ 3+ | Tìm/chọn; Apache-2.0 |
| `sweetalert2` | 11.26.25 | GĐ 3+ | Hộp xác nhận |

Chưa cài: parser XLSX (chờ benchmark G1-03 quyết định nơi parse) và thư viện biểu đồ
(Chart.js/ApexCharts chưa chốt, ApexCharts cần đối chiếu giấy phép).

### Mã thử nghiệm GĐ 0 trong repository

Mã spike Auth/audit được giữ và commit cùng cấu hình chính thức, tách khỏi mã Worker:
`apps/api/src/spike-app.ts` (app spike cũ, trước là `app.ts`), `auth-bridge.ts`,
`local.ts`, `apps/api/tests/*.ts`, `scripts/auth-spike/`. Typecheck riêng bằng
`apps/api/tsconfig.spike.json`; Prettier bỏ qua để giữ nguyên làm bằng chứng.
`scripts/auth-spike/config.ts` (đã mất khi dọn GĐ 0) được tạo lại, đọc `supabase status`
và chỉ chấp nhận DB local. Schema spike được xuất chỉ đọc từ stack `mledu` ra
`supabase/spike/gd0-auth-spike.sql` — **không phải migration**; `npm run spike:db` áp
vào DB local khi cần chạy lại. Ngày 27/10/2026 `npm run test:auth:integration` chạy lại
trên stack `mledu` hiện có: 26/26 đạt. Phụ thuộc chỉ dùng cho spike (`pg`, `@types/pg`,
`@hono/node-server`) là devDependency của `apps/api`.

## Quyết định thiết kế

**Workspace.** `packages/contracts` xuất thẳng mã TypeScript (`@mledu/contracts/common`),
không có bước build riêng; Vite và Wrangler tự bundle. Một `package-lock.json` ở gốc.

**Schema được expose.** Data API chỉ expose schema `api` (`supabase/config.toml`).
Bảng nghiệp vụ nằm ở `app`, helper ở `app_private`; cả hai không cấp quyền cho
`anon`/`authenticated` và mọi bảng bật RLS. Mỗi hàm `api.*` là lệnh/truy vấn được
thiết kế, chạy `SECURITY DEFINER`, cố định `search_path` và tự kiểm tra quyền.
Migration thu hồi quyền `EXECUTE` mặc định cho `PUBLIC` với hàm do `postgres` tạo,
nên **mọi hàm cần cho client phải được `GRANT` rõ** (kể cả hàm dùng trong RLS policy
hoặc Storage policy ở các giai đoạn sau).

**Phiên và quyền tại request.** Worker chuyển JWT của người dùng tới PostgREST;
`app_private.require_account()` xác định người gọi từ database ở mỗi request:
`session_id` phải còn trong `auth.sessions` (và chưa quá `not_after`), tài khoản bật,
chưa xóa mềm, phiên không cũ hơn `sessions_valid_after`, và chưa phải đổi mật khẩu tạm
(trừ luồng đổi mật khẩu). Không dùng role/claim trong JWT để phân quyền. Lỗi trả về
bằng SQLSTATE `PTxyz` (PostgREST đổi thành HTTP xyz) với thông điệp là mã lỗi trong
hợp đồng; Worker chuyển thành `ErrorResponse` và không trả nội dung lỗi SQL.

**Audit, lịch sử, outbox.** Lệnh nghiệp vụ gọi trong cùng transaction:
`app_private.write_audit`, `record_version`, `enqueue_notification`. Audit chỉ thêm,
`created_at` do DB đặt, hết hạn đúng 1.440 giờ (60 ngày) sau khi tạo; chỉ xóa được
dòng đã hết hạn. Lịch sử và outbox event bất biến. Khóa JSON giống mật khẩu/token/
signed URL bị từ chối trong cả ba nơi. Outbox chống trùng theo `event_key` và cặp
sự kiện/người nhận, nên tác vụ chạy lại không nhân đôi. Request ID từ Worker được ghi
vào audit.

**Môi trường.** `wrangler.jsonc` có cấu hình gốc cho local và hai môi trường
`staging`, `production` riêng; secret đặt bằng `wrangler secret put`, không nằm trong
Git hoặc `VITE_*`. Không có workflow deploy; production chỉ deploy sau phê duyệt GĐ 10.

## Phần cố ý chưa làm ở GĐ 1

| Nội dung | Giai đoạn/mục xử lý |
| --- | --- |
| Bảng `notifications`, `background_jobs`, `job_attempts`, Cron dọn audit 60 ngày, phân phối outbox | GĐ 9 |
| Cột `import_id`/`job_id` của audit, `class_id` của outbox | Thêm cùng bảng đích (GĐ 8/9/3) |
| Access Token Hook, lệnh Auth có audit nguyên khối, self-service mật khẩu | G1-05, GĐ 2 |
| Bucket `avatars`, Storage policy, luồng avatar | G1-02, GĐ 2 |
| `npm run test:performance` | G1-03 (benchmark Excel) |
| i18n Việt/Anh, theme, layout theo quyền | GĐ 2 |

## Bằng chứng (local, 26/10/2026)

Chạy trên Windows 11, Docker Desktop, Supabase local CLI 2.120.0 (PostgreSQL 17).

| Lệnh | Kết quả |
| --- | --- |
| `npm run lint`, `npm run format:check`, `npm run typecheck` | Đạt |
| `npm run test:unit` | 17/17 đạt (contracts 3, API trong workerd 10, web 4) |
| `npm run test:db` | 51/51 pgTAP đạt: quyền expose 14, phiên theo request 11, nguyên khối lệnh 26 |
| `npm run test:integration` | 7/7 đạt: health/ready qua entrypoint Worker; đủ ba loại tài khoản; chờ đổi mật khẩu 403; tài khoản khóa 401; token còn hạn sau khi đăng xuất 401; token giả 401 |
| `npm run test:e2e` | 4/4 đạt (desktop + mobile): SPA gọi được Worker; deep link lạ hiển thị trang 404 của SPA |
| `npm run build` + `npm run check:artifacts` | Đạt; không có secret/đường dẫn `template/` trong `apps/web/dist`, `apps/api/dist` |
| Clone sạch nhánh → `npm ci` → typecheck → build → check | Đạt, không có thư mục `template/` |

Kiểm tra độ nhạy: sửa tạm lệnh mẫu để "nuốt" lỗi audit thì 6/26 test nguyên khối
thất bại; chèn tạm một `sb_secret_…` giả hoặc source map trỏ vào `template/` vào
`dist` thì `check:artifacts` báo lỗi. Các thay đổi tạm này không nằm trong mã.

Lần chạy kiểm chứng dùng một Supabase local riêng (project `mledu-gd1test`, cổng
554xx) để không reset stack `mledu` và API thử nghiệm GĐ 0 đang chạy trên máy;
`npm run test:e2e` dùng cổng riêng 8797/5183 và không tái sử dụng server có sẵn.
