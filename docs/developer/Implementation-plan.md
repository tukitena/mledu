# MLedu Implementation Plan — Lộ trình và cấu trúc thư mục đề xuất

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Triển khai hệ thống MLedu đúng đặc tả hiện hành, có kiểm chứng quyền, giao dịch, lịch sử và khả năng vận hành trước khi đưa dữ liệu thật vào.

**Architecture:** Vue SPA được phục vụ bằng Cloudflare Pages; nghiệp vụ đi qua API Workers/Hono rồi tới Supabase PostgreSQL/RPC. Auth, Realtime và truyền file có luồng kết nối trực tiếp được giới hạn; API vẫn kiểm tra và xác nhận mọi thay đổi nghiệp vụ cần audit. Avatar dùng `account_profiles.avatar_path`, file ở bucket private `avatars`.

**Tech Stack:** Vue 3, TypeScript, Vite, Vue Router, Bootstrap 5/SCSS; Cloudflare Workers/Hono; Supabase Auth, PostgreSQL, Storage, Realtime và Cron. Đề xuất npm workspaces để quản lý frontend, API và contracts trong một repository.

**Spec:** [Đặc tả nghiệp vụ](../../developer/plans.md), [tech stack và ranh giới hệ thống](../../developer/techstack-va-chi-phi.md), [ERD](../../diagrams/architecture.drawio) và [giải thích mô hình](../../diagrams/README.md).

Ngày lập: **26/10/2026**. **Giai đoạn hiện hành: GĐ 1.** Đã đóng đợt thử nghiệm GĐ 0 theo quyết định của người dùng; xem [biên bản chốt và công việc chuyển tiếp](decisions/gd0-closeout.md). Các tiêu chí chưa đạt/chưa thử vẫn giữ trạng thái chưa nghiệm thu, không thay đổi đặc tả. Chưa khởi tạo ứng dụng đầy đủ hoặc triển khai production. Mỗi giai đoạn cần được tách thành các task nhỏ khi bắt đầu thực hiện; tài liệu này không thay thế 60 tiêu chí nghiệm thu trong đặc tả.

## Global Constraints — Ràng buộc xuyên suốt

- `plans.md` là nguồn nghiệp vụ; tài liệu này và ERD không được nới hoặc tự thay đổi các quy tắc đã chốt.
- Nghiệp vụ: Vue → Workers/Hono → PostgreSQL/RPC. UI ẩn nút không thay thế kiểm tra quyền; quyền và phiên được xét tại request.
- Một lệnh nhiều bước phải nguyên khối với audit và yêu cầu thông báo bắt buộc. Không ghép nhiều request ghi độc lập rồi coi là một transaction.
- Dùng `Asia/Ho_Chi_Minh`; ngày nghỉ loại trừ từ 00:00; sự kiện giữa ngày dùng timestamp thực tế. Gia hạn/khôi phục không hồi sinh khoảng đã kết thúc.
- Lịch sử nghiệp vụ giữ không thời hạn; audit và thông báo giữ đúng 60 ngày từ lúc tạo. Không dùng audit làm nguồn duy nhất để phục hồi dữ liệu.
- Không có tenant hoặc quyền theo địa điểm; không tạo tài khoản phụ huynh. Tra cứu phụ huynh đi qua endpoint Workers được giới hạn dữ liệu/tần suất.
- Tiền VND nguyên đồng. Không thanh toán từng phần, quá hạn, giảm theo phần trăm hoặc tự chia học phí theo buổi/ngày.
- Avatar: JPG/PNG/WebP, tối đa 5.000.000 byte; chỉ chủ tài khoản tự đổi. DB lưu path tương đối hoặc NULL; bucket private; backend kiểm tra file thực tế.
- Excel: chỉ `.xlsx` theo mẫu; dưới 10.000.000 byte, tối đa 5.000 dòng; không thực thi công thức; một lỗi chặn cả file, một lần thành công có một audit.
- `template/` chỉ để tham khảo và bị ignore; không import, symlink, lấy dependency/config hoặc đọc nó khi build/runtime. `.agents/` là cài đặt cục bộ bị ignore.
- Không đưa secrets vào mã nguồn, `VITE_*`, contracts, log, audit hoặc artifact frontend. Publishable key không phải quyền ghi rộng vào dữ liệu.
- Chỉ tạo các thư mục/module khi giai đoạn thực sự cần; không sinh hàng loạt file rỗng hoặc triển khai toàn bộ 54 thực thể trong một migration khổng lồ.

## Review Focus — Năm nhóm lỗi cần kiểm chứng sớm

| Rủi ro | Kết quả bắt buộc | Giai đoạn chịu trách nhiệm |
| --- | --- | --- |
| Token cũ sau khóa/đổi quyền/hết phân công; Auth API và audit DB ở hai hệ thống | Request kế tiếp dùng quyền hiện hành; thao tác Auth không được tuyên bố đạt atomicity khi chưa chứng minh | GĐ 0, 2, 10 |
| Xóa/thêm lại hoặc kết thúc giữa ngày làm lẫn hồ sơ, học vụ và khoản tiền | Học vụ theo học sinh/bài/buổi; tiền theo hồ sơ lớp; quá khứ giữ nguyên | GĐ 3–7, 10 |
| Hai người đặt phòng/thu cùng khoản/xác nhận cùng file | Chỉ một kết quả hợp lệ; không ghi trùng hoặc cập nhật một phần | GĐ 4, 6, 8 |
| File avatar giả MIME, upload xong nhưng audit lỗi, hai lần đổi ảnh đồng thời | File sai bị chặn; path cũ còn hiệu lực khi commit lỗi; không xóa ảnh đang dùng | GĐ 2 |
| Excel cực đại và lỗi nền tảng/gián đoạn tác vụ | Đủ 5.000 dòng/50 phần; nguyên khối toàn file; chạy bù đúng lịch sử, không tạo trùng | GĐ 0, 8, 9 |

## 1. Cấu trúc repository đề xuất

Đề xuất dùng một repository với ba workspace: `apps/web`, `apps/api`, `packages/contracts`. Chỉ có một lockfile `package-lock.json` ở gốc. Đây là lựa chọn tổ chức source đề xuất, không lấy cấu hình từ Metis. [npm workspaces](https://docs.npmjs.com/cli/using-npm/workspaces/) hỗ trợ liên kết các package cục bộ từ package gốc.

```text
mledu/
├── apps/
│   ├── web/                             # Vue SPA → Cloudflare Pages
│   │   ├── package.json
│   │   ├── vite.config.ts
│   │   ├── tsconfig.json
│   │   ├── .env.example                 # Chỉ cấu hình công khai
│   │   ├── public/                      # Tài nguyên tĩnh được phép công khai
│   │   └── src/
│   │       ├── main.ts
│   │       ├── App.vue
│   │       ├── app/                     # Router, layout, bootstrap, state phiên/UI
│   │       ├── features/                # Màn hình và logic theo nghiệp vụ
│   │       │   ├── auth/
│   │       │   ├── profile/             # Hồ sơ cá nhân và avatar
│   │       │   ├── students/
│   │       │   ├── classes/
│   │       │   ├── catalogs/
│   │       │   ├── scheduling/
│   │       │   ├── attendance/
│   │       │   ├── assessments/
│   │       │   ├── comments/
│   │       │   ├── fees/
│   │       │   ├── portal/
│   │       │   ├── imports/
│   │       │   ├── notifications/
│   │       │   ├── audit/
│   │       │   └── dashboard/
│   │       ├── components/              # Component UI dùng lại, không chứa quyền DB
│   │       ├── lib/
│   │       │   ├── api-client.ts        # Gọi Workers, JWT, lỗi và request ID
│   │       │   ├── supabase-auth.ts
│   │       │   └── supabase-realtime.ts
│   │       ├── locales/                 # vi/en
│   │       ├── styles/                  # Bootstrap/SCSS và CSS in
│   │       └── assets/                  # Asset thuộc source chính thức
│   └── api/                             # Hono → Cloudflare Workers
│       ├── package.json
│       ├── wrangler.jsonc
│       ├── tsconfig.json
│       ├── vitest.config.ts
│       ├── .dev.vars.example            # Tên biến backend, không chứa secret thật
│       ├── src/
│       │   ├── index.ts                 # Entrypoint Worker
│       │   ├── app.ts                   # Ghép middleware và route Hono
│       │   ├── env.ts                   # Kiểu/config bindings
│       │   ├── middleware/              # Phiên, request ID, lỗi, giới hạn tần suất
│       │   ├── lib/                     # Client DB theo user/admin, Storage adapter
│       │   ├── modules/                 # Domain tương ứng frontend + jobs/outbox
│       │   │   ├── profile/
│       │   │   │   ├── routes.ts
│       │   │   │   ├── service.ts
│       │   │   │   └── service.test.ts
│       │   │   ├── auth/
│       │   │   ├── students/
│       │   │   ├── classes/
│       │   │   ├── catalogs/
│       │   │   ├── scheduling/
│       │   │   ├── attendance/
│       │   │   ├── assessments/
│       │   │   ├── comments/
│       │   │   ├── fees/
│       │   │   ├── portal/
│       │   │   ├── imports/
│       │   │   ├── notifications/
│       │   │   ├── audit/
│       │   │   ├── dashboard/
│       │   │   └── jobs/
│       │   └── generated/
│       │       └── database.types.ts    # Kiểu DB sinh từ migration/schema hợp lệ
│       └── tests/integration/           # HTTP + DB/Storage, gồm đồng thời và lỗi
├── packages/
│   └── contracts/                       # DTO, enum và schema request/response
│       ├── package.json
│       └── src/
│           ├── common.ts                # Phân trang, lỗi, version
│           ├── profile.ts
│           └── ...                      # Tách theo domain khi cần
├── supabase/
│   ├── config.toml
│   ├── migrations/                      # SQL version hóa: bảng, RLS, RPC, index, Cron
│   ├── seed.sql                         # Chỉ dữ liệu giả/kiểm thử cục bộ
│   └── tests/database/                  # pgTAP cho constraint/RLS/RPC và rollback
├── tests/
│   ├── e2e/                             # Luồng trình duyệt theo vai trò
│   ├── performance/                     # Excel cực đại, RPC và truy vấn lớn
│   └── fixtures/                        # Dữ liệu giả, không chứa thông tin thật
├── scripts/
│   ├── dev/                             # Công cụ phục vụ phát triển
│   └── ops/                             # Quản trị Admin có kiểm soát/audit, vận hành
├── docs/
│   ├── developer/                       # plans.md, tech stack, hướng dẫn hiện có
│   ├── diagrams/                        # ERD và giải thích mô hình
│   ├── superpowers/plans/               # Lộ trình này và kế hoạch triển khai chi tiết
│   └── operations/                      # Runbook deploy, backup/restore, xử lý lỗi
├── .github/workflows/                   # CI, staging và production
├── .agents/                             # Cục bộ, bị ignore
├── template/                            # Tham khảo, bị ignore
├── package.json                         # private + khai báo workspaces + scripts chung
├── package-lock.json
├── tsconfig.base.json
├── .gitignore
└── README.md
```

### Trách nhiệm và chiều phụ thuộc

| Thành phần | Trách nhiệm | Phụ thuộc được phép |
| --- | --- | --- |
| `apps/web` | UI, route, gọi API, phiên trình duyệt, nhận tín hiệu Realtime | `packages/contracts`, cấu hình công khai |
| `apps/api` | Kiểm tra request/phiên, điều phối upload/Excel, gọi RPC, truy vấn theo quyền | `packages/contracts`, client Supabase được giới hạn |
| `packages/contracts` | Hợp đồng dữ liệu truyền qua HTTP | Kiểu/schema thuần; không secret, không client admin hoặc mã Worker |
| `supabase/migrations` | Ràng buộc, RLS, khóa, transaction/RPC, audit/outbox nguyên khối | SQL version trước đó; không đọc `template/` |
| `tests/e2e` | Kiểm tra hành vi hệ thống qua giao diện/API | Bản chạy local/staging và fixture giả |
| `scripts/ops` | Công cụ vận hành có quyền và audit theo AUTH-06 | Credential vận hành ngoài Git, API/helper được thiết kế |

Trong mỗi feature, đặt component/page/API adapter và test cạnh nghiệp vụ. Chỉ đưa thành phần thực sự dùng lại vào `components/` hoặc `lib/`. API service điều phối; logic cần nguyên khối nằm trong RPC, tránh sao chép luật tài chính/phân quyền ở cả Vue, Hono và nhiều câu SQL rời.

SQL trong migration là nguồn triển khai chính. Không duy trì thêm một bộ SQL thủ công song song có thể lệch schema. Kiểu DB sinh lại sau migration; DTO trả cho frontend chỉ chứa dữ liệu được phép, không xuất toàn bộ row DB thành hợp đồng công khai.

### Giao tiếp và cấu hình môi trường

- API dùng prefix đề xuất `/v1`. Vue gọi một API base URL theo môi trường; CORS chỉ cho origin hợp lệ, không coi CORS là cơ chế phân quyền.
- Đăng nhập/refresh thông thường dùng Auth SDK. Các thay đổi tài khoản/xác thực cần audit đi qua luồng đã kiểm chứng ở GĐ 0–2; không cho SDK bỏ qua nghiệp vụ.
- Realtime phát tín hiệu tối thiểu. Khi có tín hiệu hoặc kết nối lại, Vue lấy dữ liệu qua API có quyền hiện hành.
- `apps/web/.env.example` chỉ có API base URL, Supabase URL và publishable key. Secret/admin key và thông tin vận hành nằm trong Worker secrets hoặc kho secrets của CI, không trong `VITE_*`.
- Tách local/staging/production. Không trỏ test tự động hoặc `db reset` vào production. Migration production là thay đổi tiến, có backup và phương án phục hồi dữ liệu; rollback frontend không được giả định tự đảo migration DB.
- Build Pages chỉ lấy `apps/web/dist`; Worker chỉ lấy entrypoint/build của `apps/api`. Không upload toàn bộ repository.

### Hợp đồng avatar đề xuất

| Endpoint | Input chính | Output/hành vi |
| --- | --- | --- |
| `POST /v1/me/avatar/uploads` | Tên/loại/kích thước khai báo để kiểm tra ban đầu | API tạo path mới thuộc user hiện hành trong `avatars`, cấp quyền upload giới hạn; client không chọn bucket/user tùy ý |
| `POST /v1/me/avatar` | `{ path, expectedVersion }` | Backend xác minh file thực tế, rồi RPC cập nhật path + version + audit; trả hồ sơ hiện hành |
| `GET /v1/me` | JWT hợp lệ | Trả hồ sơ được phép và thông tin avatar cần hiển thị; URL đọc có chữ ký được sinh khi cần |

DTO tương ứng đặt trong `packages/contracts/src/profile.ts`; route/service nằm ở `apps/api/src/modules/profile/`. `avatar_path` trong DB là path tương đối, không gồm tên bucket hoặc hostname. Path mới phải duy nhất và có định dạng ảnh đúng với file đã kiểm tra. RPC kiểm soát version để hai lần đổi ảnh không ghi đè âm thầm. Dọn file chỉ sau khi xác nhận file không còn được dùng. Signed URL và DB transaction không tạo thành một transaction phân tán; lỗi trước commit phải giữ avatar cũ.

## 2. Thứ tự các giai đoạn

| Giai đoạn | Kết quả chính | Phụ thuộc |
| --- | --- | --- |
| 0 — Đã đóng đợt thử nghiệm | Kết quả local Auth/audit và hồ sơ bàn giao; các gate còn lại được liệt kê riêng | Đặc tả + ERD; xem biên bản chốt |
| 1 — Hiện hành | Workspace, môi trường, CI và nền DB/RLS/audit/outbox | Kết quả GĐ 0 + công việc chuyển tiếp G1-01–05 |
| 2 | Tài khoản, phiên, hồ sơ cá nhân và avatar end-to-end | GĐ 1; gate Auth ở GĐ 0 |
| 3 | Danh mục, học sinh, lớp, phân công và khoảng tham gia | GĐ 1–2 |
| 4 | Lịch thực tế, phòng và điểm danh | GĐ 3 |
| 5 | Bài kiểm tra, điểm, nhận xét và công bố | GĐ 3 |
| 6 | Học phí, khoản ngoài, thu và gỡ sai | GĐ 3–4 |
| 7 | Trang lớp và tra cứu phụ huynh đúng phạm vi | GĐ 2–6 |
| 8 | Đồng bộ Excel theo các lệnh nghiệp vụ đã có | GĐ 3–6 + benchmark GĐ 0 |
| 9 | Cron/chạy bù, thông báo, vòng đời liên miền, in/dashboard | GĐ 3–8; nền audit/outbox đã có từ GĐ 1 |
| 10 | Nghiệm thu tích hợp, diễn tập phục hồi và đưa vào vận hành | Tất cả giai đoạn trước |

GĐ 4 và 5 có thể triển khai độc lập sau khi mô hình lớp/phân công ổn định; bảng phụ thuộc không đồng nghĩa yêu cầu dùng nhiều agent. Chưa ước lượng số tuần vì chưa có tốc độ nhóm và kết quả thử nghiệm nền tảng. Mỗi giai đoạn hoàn thành theo tiêu chí nghiệm thu, không theo việc đã dựng đủ màn hình.

### Giai đoạn 0 — Kiểm chứng các rủi ro nền tảng

**Trạng thái: đóng đợt thử nghiệm ngày 26/10/2026 theo quyết định chuyển giai đoạn.**
Giữ các checkbox nghiệm thu chưa đạt/chưa thử bên dưới để không làm mất việc;
[G1-01–05](decisions/gd0-closeout.md) ghi rõ nơi xử lý và điều kiện trước khi
nghiệm thu Auth/avatar hoặc chốt parser/migration. Nhóm tích hợp local đạt 26/26;
toàn bộ test nhanh đạt 35/38, ba gate recovery native còn đỏ.

**Đầu ra:** Biên bản thử nghiệm và quyết định kỹ thuật, chưa phải chức năng production. Nơi lưu dự kiến: `docs/developer/decisions/auth-audit.md`, `avatar-storage.md`, `excel-benchmark.md`.

- [ ] Thử AUTH-01–08 trên môi trường giả lập/staging: mật khẩu tạm, reset 5 phút/một lần, cấp lại vô hiệu link cũ, token cũ sau khóa/đổi quyền/đăng xuất, tài khoản xóa mềm và email giữ lại.
- [ ] Tiêm lỗi giữa Auth Admin API và ghi audit; xác định cơ chế đáp ứng yêu cầu nguyên khối. Nếu chưa chứng minh được, ghi rõ điểm chặn và thống nhất điều chỉnh triển khai/yêu cầu trước khi nghiệm thu nhóm Auth; không coi một outbox hoặc tác vụ bù là tự động giải quyết atomicity này.
- [ ] Thử upload private, xác minh file và cập nhật path/audit; kiểm tra ảnh giả MIME, file vượt 5.000.000 byte, audit lỗi và hai lần đổi ảnh đồng thời.
- [ ] Benchmark parser với `.xlsx` gần giới hạn dung lượng, 5.000 dòng và bài 50 phần; đo CPU, bộ nhớ, staging và timeout RPC. Nếu cần tiến trình parse riêng thì ghi thiết kế bổ sung trước khi tạo hạ tầng mới.
- [ ] Review ERD với 60 chức năng; xác nhận khóa học vụ khác khóa tài chính, khoảng thời gian, SQL constraint/RPC và cách giữ lịch sử.

**Gate:** Có số đo và bằng chứng cho từng thử nghiệm; điểm chưa đạt có phạm vi và quyết định xử lý. Không đánh dấu Auth đạt chỉ vì đăng nhập thành công hoặc Excel đạt vì file nhỏ chạy được.

### Giai đoạn 1 — Nền dự án, môi trường và kiểm thử

**Trạng thái: giai đoạn hiện hành, bắt đầu từ nền workspace/local/CI.** Theo dõi
đồng thời G1-01–05 trong biên bản chốt GĐ 0. Chỉ tái sử dụng phần đã được review;
schema `spike_private` và API chạy Node local chưa thay cho schema/runtime chính thức.

**Tệp đầu vào triển khai:** package/config ở gốc, `apps/web/src/main.ts`, `apps/api/src/index.ts`, `packages/contracts/src/common.ts`, `supabase/config.toml`, migration nền và `.github/workflows/ci.yml`.

- [ ] Khởi tạo npm workspaces, khóa phiên bản runtime/dependency đã kiểm tra tương thích, TypeScript, lint/format và scripts chung. Không dùng package/config của template.
- [ ] Chạy được Vue và Worker cục bộ, kết nối Supabase local; có API health check không trả secret, request ID và lỗi HTTP nhất quán.
- [ ] Thiết kế schema/quyền được expose, client theo JWT và helper quyền hạn chế. Tạo nền version/lịch sử, audit và outbox trước khi viết lệnh nghiệp vụ đầu tiên.
- [ ] Viết phép thử RPC mẫu: cập nhật + audit + yêu cầu thông báo cùng thành công; audit/outbox lỗi thì rollback tất cả. Tạo dữ liệu giả có đủ ba loại tài khoản.
- [ ] Thiết lập CI build/typecheck/test; build thử khi không có `template/`. Tạo cấu hình staging/production riêng, chưa bật deploy production tự động.

**Kiểm chứng dự kiến:** `apps/api/tests/integration/health.test.ts`, `supabase/tests/database/command_atomicity.test.sql`; Vue/Worker build thành công từ checkout sạch và đúng artifact.

### Giai đoạn 2 — Xác thực, phân quyền, hồ sơ và avatar

**Phạm vi:** AUTH-01–08, phần nền UX-01. Tệp chính: `apps/web/src/features/auth/`, `apps/web/src/features/profile/`, `apps/api/src/modules/auth/`, `apps/api/src/modules/profile/`, `packages/contracts/src/profile.ts`, migration tài khoản/quyền và Storage policy.

- [ ] Triển khai đăng nhập, buộc đổi mật khẩu, reset và quản lý phiên theo kết quả được chứng minh ở GĐ 0. Tài khoản Admin được quản trị qua công cụ vận hành có audit.
- [ ] Thử request với token cũ sau khóa/xóa/đổi loại tài khoản. Kiểm tra yêu cầu đổi mật khẩu và trạng thái hiện hành tại API/RLS/RPC; không chỉ đọc role cũ trong JWT.
- [ ] Triển khai hồ sơ cá nhân và ba endpoint avatar ở trên; xác minh file thực tế rồi ghi `avatar_path` cùng audit. Thử xung đột version và dọn file không còn tham chiếu.
- [ ] Dựng layout/workspace theo quyền, Việt/Anh và sáng/tối/theo hệ thống lưu trên trình duyệt. Tính năng chưa đủ điều kiện phải bị backend chặn dù gọi trực tiếp HTTP.

**Gate:** `apps/api/tests/integration/auth-session.test.ts`, `avatar.test.ts`, `supabase/tests/database/account_access.test.sql`, `tests/e2e/auth.spec.ts` kiểm tra đủ tình huống Review Focus. Người khác không đổi được avatar; secret không nằm trong bundle web.

### Giai đoạn 3 — Dữ liệu lõi, danh mục, lớp và lần tham gia

**Phạm vi:** STU-01–04, CLASS-01–04, CAT-01; nền trạng thái/lịch sử cho CLASS-05, SCHED-03/05. Tệp theo các module `catalogs/`, `students/`, `classes/` và migration tương ứng.

- [ ] Tạo danh mục môn/khối/địa điểm/phòng; chuẩn hóa và kiểm tra duy nhất kể cả bản lưu trữ. Phòng chỉ có tên và địa điểm theo nghiệp vụ.
- [ ] Tạo hồ sơ học sinh, nhiều số liên hệ, chuẩn hóa tên/SĐT và chống trùng đồng thời theo STU-04; mã học sinh giữ ổn định qua xuất/nhập và khôi phục.
- [ ] Tạo lớp, phân công theo thời hạn và hồ sơ học sinh–lớp chứa nhiều lần tham gia. Kiểm tra không chồng khoảng, khóa ngày đã lưu và cắt khoảng bằng sự kiện.
- [ ] Thực hiện chuyển lớp trong một RPC, phân biệt học lại trong hồ sơ cũ với xóa rồi thêm hồ sơ mới. Chuẩn bị hợp đồng vòng đời lớp để lịch/phí đăng ký xử lý nguyên khối ở GĐ 4/6/9.

**Gate:** `student-identity.test.sql`, `participation-periods.test.sql`, `class-assignment.test.sql`, `class-transfer.test.ts` kiểm tra tên trùng/SĐT chung, kết thúc giữa ngày, phân công chồng, gia hạn sau khi đã nghỉ và rollback chuyển lớp. Chưa nghiệm thu toàn bộ CLASS-05 trước khi hoàn tất xử lý liên miền ở GĐ 9.

### Giai đoạn 4 — Lịch, phòng, nghỉ lễ và chuyên cần

**Phạm vi:** SCHED-01–06, ATT-01. Module `scheduling/`, `attendance/`; migration lịch tuần có mốc áp dụng, buổi thực tế và exclusion phòng.

- [ ] Sinh buổi thực tế có khóa chống trùng từ lịch tuần; giữ ngoại lệ, buổi nghỉ/bù và thông tin phòng/địa điểm lịch sử.
- [ ] Đổi từng buổi/lịch tuần và áp dụng/bỏ lễ sau preview/xác nhận; không đổi hoặc dựng lại buổi đã bắt đầu. Buổi nghỉ/gỡ không chiếm phòng.
- [ ] Chặn hai request đặt cùng phòng chồng giờ bằng cơ chế DB có kiểm thử đồng thời. Trùng nhân sự chỉ cảnh báo; phòng được để trống.
- [ ] Điểm danh theo thời điểm buổi và khoảng tham gia; lần lưu đầu ghi Có mặt/Vắng đúng danh sách, chưa lưu là null. Ghi chú/lịch sử giữ theo học sinh/buổi.

**Gate:** `room-concurrency.test.ts`, `schedule-history.test.sql`, `attendance-scope.test.sql`, `tests/e2e/scheduling.spec.ts`. Hai buổi liền giờ hợp lệ; đổi phòng/ngày lễ không viết lại quá khứ; buổi cũ xét đúng học sinh dù hiện tại đã nghỉ.

### Giai đoạn 5 — Học vụ, thang điểm, nhận xét và công bố

**Phạm vi:** TEST-01–06, COMMENT-01–03, ACAD-01. Module `assessments/`, `comments/`; migration cấu hình/phiên bản/mức chữ/kết quả và quyền học vụ.

- [ ] Tạo bài số/phân số/chữ, mẫu chữ của lớp 1–20 mức và bản chụp theo bài; chế độ trực tiếp hoặc theo 1–50 phần.
- [ ] Lưu điểm chính xác, Vắng riêng, phần chưa nhập khác 0; tổng theo phần do backend tính, phân số giữ tổng số câu toàn bài và không rút gọn.
- [ ] Nhận xét gắn bài/đợt có khóa và công bố riêng. Đợt chỉ có tên nghiệp vụ; thời điểm tạo từng nhận xét là mốc lọc lịch sử.
- [ ] Đổi cấu hình phải hủy công bố, giữ phiên bản cũ, nhập lại điểm và giữ Vắng. Xóa/khôi phục cả bài/đợt nguyên khối, khôi phục về chưa công bố.

**Gate:** `grading-config.test.sql`, `publication-lock.test.sql`, `tests/e2e/academics.spec.ts` kiểm tra 1.001 ký tự, hơn hai số lẻ, thiếu phần, Vắng, thang đổi, trợ giảng không công bố và xóa/thêm hồ sơ không nhân đôi kết quả.

### Giai đoạn 6 — Nghĩa vụ, điều chỉnh, thu và gỡ sai

**Phạm vi:** FEE-01–11. Module `fees/`; migration kỳ, phiên bản mức, khoản phải thu, điều chỉnh, khoản ngoài, lần thu/chi tiết và sự kiện gỡ.

- [ ] Cấu hình hình thức thu bất biến, mức từng tháng hoặc kỳ không chồng; nghĩa vụ theo hồ sơ và giao đồng thời giữa kỳ, tham gia và khoảng lớp Mở.
- [ ] Giữ mức gốc tại lúc tạo, điều chỉnh cố định theo phiên bản và trạng thái Không phải thu khi tổng bằng 0. Khoản ngoài theo đối tượng/thời điểm/lần phát sinh riêng.
- [ ] Thu đủ nhiều khoản trong một RPC; kiểm tra cùng học sinh/lớp, version và khóa chống thu trùng. Thu trước tạo khoản + chi tiết + audit trong cùng giao dịch.
- [ ] Admin gỡ sai một/nhiều chi tiết, giữ snapshot cũ; thu lại tạo lần mới. Giữ nợ hợp lệ của hồ sơ lưu trữ, hủy nghĩa vụ không còn đối tượng theo đúng quy tắc.

**Gate:** `fee-obligations.test.sql`, `payment-concurrency.test.ts`, `payment-void.test.sql`, `tests/e2e/fees.spec.ts` kiểm tra nghỉ/học lại, hồ sơ mới cùng kỳ, gốc không đổi sau sửa mức, delta âm, 0 đồng, thu trước, gỡ chọn lọc và audit lỗi rollback toàn bộ.

### Giai đoạn 7 — Trang lớp và tra cứu phụ huynh

**Phạm vi:** PORTAL-01–03. Module `portal/`; endpoint tra cứu công khai trên Workers, chính sách link và bộ dữ liệu phản hồi được giới hạn.

- [ ] Trang lớp chỉ công khai nội dung/nhân sự được phép; giáo viên hiện hành/Admin sửa mô tả/thông báo, lễ tân/trợ giảng không sửa.
- [ ] Bật/tắt/reroll link có xác nhận và audit; token cũ hết hiệu lực. Tra số chuẩn hóa chỉ trả con trong đúng lớp, không trả gợi ý hồ sơ khác.
- [ ] Lọc học vụ theo công bố và hợp khoảng tham gia; tiền theo đúng hồ sơ/kỳ, không làm mất thu trước hoặc trả nợ sau nghỉ. Chặn lớp xóa, link tắt và hồ sơ lớp đã xóa chưa thêm lại.
- [ ] Kiểm tra giới hạn tần suất, cache và response schema: không ghi chú nội bộ, audit, học vụ chưa công bố hoặc dữ liệu học sinh khác.

**Gate:** `portal-visibility.test.ts`, `tests/e2e/parent-portal.spec.ts` kiểm tra nhiều con chung số, reroll, khoảng nghỉ giữa ngày, lớp đóng/xóa và học sinh thêm lại. Số không khớp không trả gợi ý.

### Giai đoạn 8 — Đồng bộ Excel có preview và xác nhận

**Phạm vi:** XLS-01–06. Module `imports/`, fixture giả và `tests/performance/excel-import.test.ts`.

- [ ] Xuất đúng mẫu từng chức năng với mã/phiên bản và `_Meta`; parser không thực thi công thức, không đoán lại hồ sơ khi mã được cung cấp sai.
- [ ] Upload private, kiểm tra/staging/preview có lỗi dòng/cột; chưa thay dữ liệu. Ô trống giữ nguyên, `XÓA` xử lý theo loại trường và khóa công bố.
- [ ] Xác nhận kiểm tra lại quyền, khoảng tham gia, version/công bố/lưu trữ và hash; một transaction áp dụng toàn file, một audit, dấu thành công giữ không thời hạn.
- [ ] Thử file tối đa và đồng thời hai lần xác nhận cùng nội dung/phạm vi. Preview/hủy/lỗi/không thay đổi không đánh dấu nhập thành công.

**Gate:** `import-atomicity.test.ts`, `import-deduplication.test.ts`, `tests/e2e/imports.spec.ts`. File 5.001 dòng hoặc đạt 10.000.000 byte bị từ chối; 5.000 dòng hợp lệ không bị cắt. Audit lỗi không để lại thay đổi một phần.

### Giai đoạn 9 — Tác vụ, thông báo và hoàn thiện các luồng liên miền

**Phạm vi:** AUD-01, NOTIF-01, CLASS-05, REPORT-01, DASH-01; tích hợp STU/CLASS/SCHED/FEE. Module `jobs/`, `notifications/`, `audit/`, `dashboard/`, màn hình in và `docs/operations/`.

- [ ] Bật Supabase Cron quét ít nhất mỗi 5 phút, job/outbox bền vững, idempotency và lịch thử lại 1/5/15 phút rồi mỗi giờ, tối đa 24 giờ; lỗi dữ liệu chờ thay đổi liên quan.
- [ ] Nghiệm thu trọn luồng đóng/mở/xóa/khôi phục lớp và kết thúc/hủy tham gia: giữ quá khứ, xử lý buổi tương lai/đăng ký/nghĩa vụ cùng một lệnh và audit. Mở lại kiểm tra phòng/lễ và không tạo bù thời gian đóng.
- [ ] Giao thông báo đúng người, chống trùng sự kiện/người nhận, Realtime chỉ báo thay đổi. Chặn dữ liệu tiền với User, kiểm tra quyền hiện hành khi mở đối tượng.
- [ ] Dọn audit/thông báo đúng 60 ngày; dữ liệu nghiệp vụ/phiên bản và dấu nhập thành công vẫn còn. Hoàn thiện UI lịch sử/audit cho Admin và lỗi tác vụ có thể xử lý/thử lại.
- [ ] Hoàn thiện dashboard theo vai trò, tổng tiền đúng hai mốc áp dụng/thu; in A4 điểm danh và A5 giấy báo qua trình duyệt, có preview/ngắt trang đúng.

**Gate:** `lifecycle-atomicity.test.ts`, `job-recovery.test.sql`, `retention.test.sql`, `notification-permissions.test.ts`, `tests/e2e/reports.spec.ts`. Gián đoạn rồi chạy bù không thu trùng; audit hết hạn không làm mất nợ/điểm; lớp khôi phục không hồi sinh khoảng đã kết thúc.

### Giai đoạn 10 — Nghiệm thu tích hợp và vận hành

**Đầu ra:** Bản staging đạt tiêu chí, kế hoạch đưa dữ liệu vào, checklist release và runbook phục hồi/triển khai trong `docs/operations/`.

- [ ] Lập ma trận 60 mã chức năng với bằng chứng DB/API/E2E. Chạy ma trận Admin/Receptionist/giáo viên/trợ giảng/phụ huynh và token cũ; không suy nghiệm thu từ số màn hình.
- [ ] Đo quy mô giả lập 1.500 học sinh, 100 lớp, 100 tài khoản theo đặc tả; đo tải đồng thời theo kịch bản được chấp nhận, không coi 100 tài khoản là 100 người online cùng lúc.
- [ ] Kiểm tra mobile/desktop, Việt/Anh, theme theo hệ thống, reload route SPA, reconnect Realtime, in A4/A5, Excel cực đại và bản build khi thiếu template.
- [ ] Diễn tập backup/restore DB **và** nội dung Storage riêng. Thử migration trên staging, rollback ứng dụng với schema tương thích và phục hồi dữ liệu; kiểm tra runbook xử lý job chờ Admin.
- [ ] Chuẩn bị dữ liệu khởi đầu qua công cụ có kiểm tra/audit; UAT trên staging. Sau phê duyệt release, deploy production, smoke test, theo dõi lỗi/usage và bàn giao người vận hành.

**Gate:** Không còn lỗi chặn trong ma trận nghiệm thu; điểm Auth/audit và benchmark Excel ở GĐ 0 được đóng bằng bằng chứng. Production chỉ nhận dữ liệu thật sau khi quyền, backup/restore và luồng tiền đã đạt.

## 3. Kiểm thử và lệnh kiểm chứng khi bắt đầu triển khai

Đề xuất Vitest cho unit/contract và kiểm thử Worker trong runtime Cloudflare; pgTAP cho SQL/RLS/RPC; [Playwright](https://playwright.dev/docs/intro) cho trình duyệt. Chốt phiên bản tương thích khi GĐ 0–1 chạy thực tế. Tài liệu hiện tại của Cloudflare hướng dẫn tích hợp qua `@cloudflare/vitest-plugin`; không sao chép cấu hình cũ của template. [Workers Vitest integration](https://developers.cloudflare.com/workers/testing/vitest-integration/). Supabase hỗ trợ pgTAP trong `supabase/tests/database/` và lệnh `supabase test db`. [Testing your database](https://supabase.com/docs/guides/database/testing).

Các script dưới đây là **hợp đồng scripts đề xuất để tạo ở GĐ 1**, chưa tồn tại và chưa được chạy thành công trong repository hiện tại:

```text
npm ci                     Cài từ lockfile gốc trong CI
npm run lint               Kiểm tra mã của các workspace
npm run typecheck          Kiểm tra TypeScript web/API/contracts
npm run test:unit          Unit/contract tests
npm run test:db            pgTAP trên Supabase local, gồm quyền và rollback
npm run test:integration   HTTP + Supabase local, gồm yêu cầu đồng thời
npm run test:e2e           Luồng trình duyệt local/staging
npm run test:performance   Kịch bản cực đại đã định nghĩa; không chạy trên production
npm run build              Build web và Worker, chỉ lấy source chính thức
```

Mỗi thay đổi nghiệp vụ bắt đầu từ ca kiểm thử mô tả lỗi/hành vi cần có, rồi triển khai và chạy đúng nhóm kiểm chứng liên quan. Test tiền, quyền, thời gian và transaction dùng DB/Storage thật ở local hoặc staging phù hợp; mock Supabase trả thành công không chứng minh rollback/RLS.

## 4. Những phần chưa tự động trở thành quyết định triển khai

- Cấu trúc thư mục, npm workspaces, tên endpoint, tên test và scripts là đề xuất trong kế hoạch này. Các package thực tế chỉ được tạo khi giai đoạn tương ứng bắt đầu.
- Phiên bản runtime/dependency, parser XLSX, thư viện lịch/bảng/biểu đồ và SMTP cần được chốt qua thử nghiệm theo tech stack. Kế hoạch không đặt mua compute hoặc add-on mới.
- Nếu benchmark buộc chuyển nơi parse file, phải cập nhật thiết kế và pipeline deploy tương ứng; vẫn giữ giới hạn, preview và transaction toàn file.
- Không thêm Supabase Edge Functions thành API thứ hai hoặc thêm cache/queue/database riêng mặc định. Bổ sung hạ tầng phải xuất phát từ phép đo hoặc yêu cầu cụ thể.
- Bất kỳ thay đổi nào làm khác quyền/nghiệp vụ trong `plans.md` phải được thống nhất và cập nhật nguồn đặc tả trước khi coi là tiêu chí mới.
