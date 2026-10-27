# GĐ 2 — Xác thực, phân quyền, hồ sơ và avatar

Ngày: **27/10/2026**, múi giờ Asia/Ho_Chi_Minh.

**Trạng thái: triển khai xong trên môi trường local, chờ người dùng duyệt và commit.**
Chưa chạy CI trên GitHub, chưa thử trên Supabase hosted/staging. Các điểm còn mở được
liệt kê ở cuối; không đánh dấu nghiệm thu toàn bộ AUTH-04/AUTH-07 trước GĐ 3.

## Phạm vi đã làm

| Mã | Nội dung | Nơi triển khai |
| --- | --- | --- |
| AUTH-01 | Bắt đổi mật khẩu tạm; chưa đổi thì API trả `password_change_required`; đổi lỗi không mất yêu cầu | `api.prepare_password_change`, `POST /v1/me/password`, trang `/change-password` |
| AUTH-02 | Reset qua email (link 5 phút, một lần, cấp lại vô hiệu link cũ, kết thúc mọi phiên); Admin cấp mật khẩu tạm (chỉ xem một lần) | `POST /v1/auth/password-reset[/complete]`, `POST /v1/accounts/:id/temporary-password`, template `supabase/templates/` |
| AUTH-03 | Vô hiệu hóa/kích hoạt lại; phiên cũ mất hiệu lực ngay, không hồi sinh | `api.set_account_enabled`, Access Token Hook |
| AUTH-04/05 | Xóa mềm có lý do, giữ email/lịch sử; khôi phục kích hoạt ngay, phiên cũ vẫn mất | `api.soft_delete_account`, `api.restore_account` |
| AUTH-06 | Mọi lệnh quản trị từ chối đích Admin và quyền Admin; Admin quản trị bằng công cụ vận hành có audit `source=ops` | `app_private.lock_managed_account`, `api.ops_*`, `scripts/ops/accounts.mjs` |
| AUTH-07 | Tạo tài khoản mặc định User; đổi User ↔ Receptionist, quyền mới áp dụng ngay trên phiên đang mở; UI tự cập nhật | `api.prepare_account_create`, `api.set_account_type`, đồng bộ hồ sơ mỗi 5 phút khi tab hiển thị |
| AUTH-08 | Tự sửa họ tên/SĐT/ngày sinh có version; không đổi email ở mọi đường (API, Auth SDK); đổi mật khẩu giữ phiên hiện tại, kết thúc phiên khác; avatar | `api.update_my_profile`, trigger `mledu_guard_email`, avatar bên dưới |
| UX-01 (nền) | Desktop/mobile, Việt/Anh, sáng/tối/theo hệ thống lưu theo trình duyệt; workspace theo loại tài khoản | `apps/web/src/app/{i18n,theme,session}.ts`, `AppShell.vue` |

Migration: `20261027100000_account_auth.sql`, `20261027100100_profile_avatar.sql`.

## Quyết định thiết kế

**Khóa/xóa/đổi loại không chạm Auth.** Access Token Hook
(`app_private.access_token_hook`) từ chối cấp token khi tài khoản bị khóa/xóa mềm hoặc
phiên tạo trước `sessions_valid_after`; `require_account()` kiểm tra cùng điều kiện ở
mỗi request. Vì vậy AUTH-03/04/05/07 là RPC thuần DB, ghi audit cùng transaction, không có
ranh giới Auth API + audit. Không dùng ban của GoTrue.

**Thao tác buộc phải đổi Auth dùng lệnh + deferred trigger** (thiết kế GĐ 0 đã thử, nay là
chính thức): RPC kiểm tra quyền tạo `app.auth_commands` → GoTrue thực hiện → constraint
trigger `mledu_complete_auth_command` trên `auth.users` hoàn tất lệnh trong transaction của
GoTrue (hồ sơ/cờ/lịch sử/audit). Không có lệnh hợp lệ thì GoTrue rollback. Áp dụng cho tạo
tài khoản, mật khẩu tạm (Admin/ops), tự đổi mật khẩu, reset qua email. Gọi thẳng Auth SDK
(`PUT /auth/v1/user`) để đổi mật khẩu hoặc email đều bị từ chối.

Phát hiện khi triển khai (đã xử lý, có test):

- Deferred trigger nhận `NEW` tại thời điểm INSERT, trước khi GoTrue ghi `app_metadata`;
  lúc hoàn tất phải đọc lại dòng `auth.users` hiện hành.
- GoTrue **xóa `recovery_sent_at`** trong transaction `PUT /user`; thời điểm phát hành link
  được `prepare_password_reset` ghi vào payload lệnh (đọc phía DB) và trigger kiểm tra theo đó.
- `PUT /user` giữ phiên hiện tại và xóa các phiên khác; Admin API đổi mật khẩu xóa mọi phiên
  (đo trên GoTrue v2.197.0 local). Lệnh tự đổi được xác định là lệnh mở có phiên còn tồn tại.
- Phiên mở từ link email có AMR `otp` (không có `password`); `require_account()` chỉ cho
  phiên này chuẩn bị reset (`password_reset_required` cho mọi thứ khác).

**Reset qua email trong một request Worker.** Template email trỏ về
`/reset-password?token_hash=…`; Worker verify token, chuẩn bị lệnh và đặt mật khẩu trong
cùng request, phiên từ link không tới trình duyệt (tránh fragment token, trình quét link,
PKCE theo trình duyệt). Trigger khóa dòng tài khoản nên một link chỉ đặt lại **một lần**
kể cả khi GoTrue để hai lần verify đồng thời cùng thành công (vấn đề GĐ 0). Template
magic link cũng trỏ về trang reset vì magic link dùng chung `recovery_token`.

**Avatar.** Bucket private `avatars` (5.000.000 byte, JPG/PNG/WebP), không có Storage policy
cho client. Worker cấp path dùng một lần + signed upload URL; sau upload Worker tải lại file,
kiểm tra magic bytes khớp đuôi và kích thước, đánh dấu `verified_at` bằng service role, rồi
`set_my_avatar` đổi path có version + audit. Gọi thẳng `set_my_avatar` qua Data API không qua
được bước kiểm tra. Path đã bị thay không thể được tham chiếu lại nên xóa file cũ sau commit
là an toàn; file của lần đổi thua cuộc (409) bị xóa. Ảnh được phục vụ qua `GET /v1/me/avatar`
có kiểm tra phiên mỗi lần.

**Mật khẩu tạm** do Worker sinh (12 ký tự, bỏ ký tự dễ nhầm), chỉ trả trong response của lần
cấp; không lưu, không log. Secret key chỉ có trong Worker (`.dev.vars`/Worker secrets).

**Giao diện.** Tham khảo Metis (MIT): token màu zinc + một màu nhấn, header 56px, sidebar
240px off-canvas trên mobile, trang auth hai cột; viết lại bằng Vue/SCSS của MLedu, không
import từ `template/`. Workspace chỉ là lựa chọn hiển thị; API quyết định quyền.

## Bằng chứng (local, 27/10/2026)

Windows 11, Docker Desktop, Supabase CLI 2.120.0, PostgreSQL 17.11, GoTrue v2.197.0,
Storage v1.84.19.

| Lệnh | Kết quả |
| --- | --- |
| `npm run lint`, `npm run format:check`, `npm run typecheck` | Đạt |
| `npm run test:unit` | 28/28 đạt (contracts 8, API trong workerd 16, web 4) |
| `npm run test:db` (sau `db reset`) | 135/135 pgTAP: thêm `account_access` 84 (hook, quyền, khóa/mở, đổi loại, xóa/khôi phục, lỗi audit rollback, hoàn tất lệnh Auth, reset một lần, hồ sơ, avatar) |
| `npm run test:integration` | 27/27 với GoTrue/PostgREST/Storage/Mailpit thật: `auth-session` 15 (gồm reset đồng thời 3 request → đúng 1 thành công), `avatar` 5, `session` 5, `health` 2 |
| `npm run test:e2e` | 18/18 (desktop + Pixel 7): tạo tài khoản → bắt đổi mật khẩu, khóa khi đang đăng nhập, đổi loại tới phiên mở, workspace, reset qua email, hồ sơ + avatar + ảnh giả, ngôn ngữ/theme |
| `npm run build` + `npm run check:artifacts` | Đạt; bundle web không chứa secret key (chỉ có mã kiểm tra tiền tố key của supabase-js) |

Kiểm tra thủ công trên trình duyệt: trang đăng nhập, tổng quan, tài khoản (sáng/tối),
hồ sơ ở 375px không cuộn ngang, không lỗi console.

Lưu ý chạy lại: `command_atomicity.test.sql` (GĐ 1) đếm tổng toàn bảng nên cần DB vừa
`db reset` (như CI); `account_access.test.sql` chạy được cả trên DB đã có dữ liệu test.

## Cấu hình phải làm khi lên hosted/staging

- Bật Custom Access Token Hook `pg-functions://postgres/app_private/access_token_hook`.
- Dùng template recovery/magic link như `supabase/templates/`, `Site URL` là origin SPA.
- Tắt sign-up, độ dài mật khẩu tối thiểu 8, `otp_expiry` 300 giây; giữ rate limit mặc định
  của hosted (các giới hạn nới trong `config.toml` chỉ dành cho stack local).
- Đặt `SUPABASE_SECRET_KEY` bằng `wrangler secret put`; không đưa vào `VITE_*`.

## Còn mở / chuyển tiếp

| Mục | Trạng thái |
| --- | --- |
| G1-01 recovery đồng thời | Đạt ở tầng MLedu trên local (một link một lần reset dù GoTrue verify trùng). **Chưa thử hosted**; luồng mới không dùng PKCE trình duyệt |
| G1-02 avatar | Đạt local: file giả MIME, >5.000.000 byte, người khác commit, bỏ qua Worker, đổi đồng thời, dọn file. Chưa thử hosted |
| G1-05 | Thiết kế Auth/audit đã đưa vào migration chính thức; prototype `spike_*` vẫn chỉ là tham chiếu |
| AUTH-04/07 kiểm tra phân công | Chưa có dữ liệu phân công trước GĐ 3; điểm chèn đã ghi trong `soft_delete_account`/`set_account_type`. Chưa nghiệm thu hai tiêu chí liên quan |
| Báo lỗi gửi email reset cho Admin (AUTH-02) | Hiện chỉ log vận hành; thông báo Admin thuộc GĐ 9 (NOTIF-01) |
| Dọn file avatar mồ côi (upload bỏ dở, lỗi xóa) | Bảng `avatar_uploads` đánh dấu sẵn; tác vụ dọn thuộc GĐ 9 |
| Lệnh Auth đã hết hạn trong `auth_commands` | Không chứa bí mật; chưa có tác vụ dọn (GĐ 9) |
| UI cập nhật quyền | Đồng bộ mỗi 5 phút khi đã đăng nhập và tab hiển thị; không gọi khi focus/quay lại tab. Lỗi thiếu quyền hướng dẫn tải lại trang rồi thử lại; Realtime thuộc GĐ 9 |
| CI GitHub | Chưa chạy (chưa có remote) |
