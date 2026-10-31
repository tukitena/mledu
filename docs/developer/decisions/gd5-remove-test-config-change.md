# GĐ5 — Bỏ luồng đổi cấu hình bài kiểm tra (TEST-03)

Ngày: **31/10/2026**. Theo yêu cầu trực tiếp của người dùng: bỏ hẳn luồng đổi cấu hình đánh giá/chọn lại
template cho bài kiểm tra đã tạo. Đặc tả `plans.md` mục **TEST-03** được viết lại thành "Cấu hình đánh giá cố
định sau khi tạo bài"; mã TEST-03 giữ nguyên để không đổi bộ mã yêu cầu.

## Hành vi mới

- Cấu hình (loại đánh giá, chế độ nhập, điểm tối đa, tổng số câu, mức chữ, các phần, kỹ năng IELTS) và nguồn
  template chốt khi tạo bài; không sửa, không chọn lại template sau đó, kể cả khi chưa có kết quả.
- Muốn dùng cấu hình khác: tạo bài mới; bài cũ không dùng nữa thì xóa theo TEST-06.
- Vẫn được: sửa tên/ngày/mô tả (TEST-05), bật/tắt hiện chi tiết (TEST-04, `set_test_show_components`).

## Thay đổi

Theo yêu cầu, sửa thẳng các migration lịch sử, **không thêm migration mới**:

- `20261031110000_tests.sql`: xóa `api.change_test_config` và grant; `CHECK (revision = 1)` trên
  `app.test_config_versions` (cùng `UNIQUE (test_id, revision)` → mỗi bài một snapshot); `get_test` không còn
  `configVersions`; bỏ `configRevision` khỏi DTO và `config_revision` khỏi snapshot lịch sử.
- `20261031120000_test_results.sql`: xóa bản `change_test_config` có khóa công bố/nhập lại; bỏ `configRevision`.
- `20261031130000`, `20261031150000`, `20261031160000`: bỏ `configRevision` trong `test_dto`; sửa chú thích khóa.
- `20261031140000_ielts_results.sql`: trigger xóa đầu vào IELTS không còn xét đổi `config_id`.
- API: bỏ `PUT /v1/tests/:id/config`; `GET /v1/tests/:id` trả `ClassTest`. Contracts: bỏ
  `ChangeTestConfigRequest`, `TestConfigVersion`, `ClassTestDetail`, `ClassTest.configRevision`. Generated types
  đã sinh lại từ DB và khớp.
- Web: bỏ chế độ `config` của `TestFormDialog`, menu "Đổi cấu hình", "Lịch sử cấu hình", dòng "Cấu hình #n",
  cảnh báo nhập lại, prop `showLocked` của `GradingConfigEditor` và các chuỗi i18n tương ứng. Gợi ý chọn template
  khi tạo bài nói rõ cấu hình không đổi được sau khi tạo.

Giữ lại có chủ đích: bảng `app.test_config_versions` (snapshot bất biến mà kết quả tham chiếu), cột `revision`
(luôn 1), tham số `configId` của `save_test_results` (vẫn chặn lưới gửi nhầm bài), mã lỗi `result_published`
(khóa công bố ACAD-01).

## Bằng chứng (local, 31/10/2026)

| Lệnh | Kết quả |
| --- | --- |
| `npm run test:stack:reset` + `npm run test:db` | 915/915 pgTAP (mới: không còn RPC đổi cấu hình, DB từ chối snapshot thứ hai) |
| `npm run test:db:types` | Types sinh lại khớp file đã sửa tay |
| `npm run test:db:concurrency` | 15/15 |
| `npm run test:integration` | 70/70 (mới: `PUT /v1/tests/:id/config` → 404) |
| `npm run test:unit` | contracts 31, API 17, web 12 |
| `npm run lint`, `npm run typecheck`, `npm run format:check` | Đạt |
| `npm run test:e2e -- class-tests.spec.ts test-results.spec.ts` | 8/8 desktop/mobile |

Chưa chạy toàn bộ e2e. Môi trường `mledu-dev` (đã áp migration cũ, không reset) vẫn còn hàm
`api.change_test_config` và ràng buộc cũ cho tới khi reset; vì sửa migration lịch sử, mọi DB đã áp các migration
này (dev/staging, nếu có) cần reset hoặc xử lý tay. Chưa chạy CI GitHub/hosted. Không commit/push/deploy.
