# Tách seed local và fixture kiểm thử

Ngày: 28/10/2026. Thực hiện trên `seed/isolate-fixtures`, từ `feat/core-data`,
theo yêu cầu tạo nhánh riêng rồi merge lại. Không tạo worktree.

## Bố trí được chốt

- `supabase/seeds/` chỉ còn `00-account.sql`: tài khoản tạm để mở app local.
  File vẫn được Git theo dõi theo yêu cầu; không tạo thư mục `internal`.
- Dữ liệu riêng bổ sung sau này đặt trực tiếp trong `supabase/seeds/`, bị Git ignore.
  Trước khi thay `00-account.sql` bằng tài khoản thật, phải bỏ ngoại lệ ignore và
  `git rm --cached` file đó. Không commit dữ liệu thật rồi mới ignore.
- `tests/fixtures/database/` chứa bốn file tài khoản/danh mục/học sinh/lớp giả.
  Bản tài khoản test độc lập, không include hoặc đọc seed local.
- `supabase/migrations/` là nguồn schema duy nhất. Thư mục cấu hình test trong
  `tmp/supabase-test/` được sinh từ nguồn này; không duy trì bản migrations riêng.

## Môi trường và kết nối

| | Mở app/kiểm tra thủ công | Test tự động/CI |
| --- | --- | --- |
| Project | `mledu-dev` | `mledu-test` |
| API / PostgreSQL / Mailpit | 54321 / 54322 / 54324 | 55321 / 55322 / 55324 |
| Dữ liệu | `supabase/seeds/` | `tests/fixtures/database/` |
| Cấu hình app | `.dev.vars`, `.env.local` | `tmp/supabase-test/`, không fallback sang dev |

`scripts/testing/stack.ts` sao chép chỉ migrations, templates, pgTAP và fixture vào
workdir test. Kiểm tra project và các endpoint cố định trước khi dùng; `db reset`
chỉ chạy với `--local --workdir` trỏ stack test. Tách cả Auth/Storage/volume.
Unit tests dùng bindings giả, không cần stack hay secrets dev.

Các lệnh mới: `test:stack:start`, `test:stack:reset`, `test:stack:stop`, `test:env`,
`test:db:types`, `test:tooling`. Các lệnh DB/integration/E2E/concurrency hiện có
được chuyển sang test stack; Auth spike cũng bỏ fallback sang DB đang mở app.
CI dời seed local ra khỏi checkout trước khi chạy database tests và không gọi `local:env`.

Seed local chạy khi khởi tạo/reset local, không tự chạy lại mỗi lần mở app.
Dữ liệu nội bộ cần nạp khi deploy được cung cấp từ máy triển khai riêng, ngoài CI và
bundle ứng dụng. Hiện chỉ có tài khoản tạm nên không nạp lên hosted. Không xây thêm
manifest/loader nội bộ ở lần chỉnh sửa này; tài khoản thật dùng công cụ vận hành có audit.

Đã dừng stack cũ `mledu` bằng CLI có giữ volume, khởi tạo `mledu-dev` và cập nhật
env local. DB cũ không bị reset/xóa. Sau các test và reset stack test, dev vẫn có
5 tài khoản, 0 danh mục, 0 học sinh, 0 lớp, 0 audit. Hash hai file env dev không đổi
trong quá trình kiểm thử.

## Kiểm chứng local

- 2 test công cụ: từ chối endpoint dev/remote; không đọc seed riêng/ghi đè env dev;
  chuẩn bị test được cả khi không tồn tại thư mục seed local.
- 34 unit, 350 pgTAP, 1 test khóa PostgreSQL đồng thời, 47 integration và 32 E2E
  desktop/mobile (`--workers=2`) đạt trên cấu hình mới.
- Typecheck, lint, format, build dry-run, kiểm tra artifacts và `git diff --check` đạt.
- `test:stack:reset` chỉ dựng lại DB test; `test:db:types` sinh đúng types hiện hành,
  không tạo diff.

Phát hiện cấu hình Prettier trước đây không có trong Git: checkout sạch dùng mặc định
khác style hiện có. Đưa settings vào `package.json`, theo dõi `.prettierignore` để
CI tái lập kiểm tra mà không reformat hàng loạt code/tài liệu cũ.

GitHub CI/hosted chưa chạy cho thay đổi này; không deploy hoặc push. Bộ kiểm thử
Auth spike GĐ0 lịch sử chưa được chạy lại, vẫn có điều kiện hook/schema riêng như trước.
