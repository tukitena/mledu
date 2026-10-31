# GĐ5 — Feature 2: bài kiểm tra trong lớp và snapshot cấu hình (TEST-05)

> **Cập nhật 31/10/2026:** luồng đổi cấu hình/chọn lại template của bài đã bị bỏ hẳn; cấu hình chốt khi tạo bài. Xem [quyết định bỏ đổi cấu hình bài](gd5-remove-test-config-change.md).

Ngày triển khai/kiểm chứng local: **31/10/2026**. Phạm vi: **TEST-05**, cấu hình có kiểu của
**TEST-01/04** cho từng bài, cách dùng template của **TEST-02** và tùy chọn hiện/ẩn chi tiết của **TEST-04**.
Tiếp nối [feature thư viện template](gd5-test-templates.md). **Chưa triển khai:** kết quả/điểm, IELTS tính
điểm, công bố (ACAD-01), xóa/khôi phục bài (TEST-06),
nhận xét (COMMENT-01–03). Không đổi đặc tả.

## Hành vi và dữ liệu

- Migration `20261031110000_tests.sql`: `app.tests` (thuộc lớp, cho trùng tên, `show_components` nằm ngoài
  snapshot) và snapshot quan hệ bất biến `app.test_config_versions` + `test_letter_levels` / `test_components` /
  `test_ielts_skills`, đúng phương án 2 của [thiết kế học vụ](../assessment-schema.md). Mức/phần giữ thêm cột
  `code` (`l1…`, `c1…`) theo vị trí để Excel/kết quả về sau dùng mã ổn định của snapshot.
- Cấu hình bài được validate bằng chính `app_private.test_template_config` rồi tách ra các bảng. Constraint
  trigger trì hoãn dựng lại cấu hình từ các dòng tại commit và bắt buộc nó hợp lệ, đã chuẩn hóa (bắt lỗi số
  dòng/tổng/mã mà CHECK một dòng không chứng minh được), kể cả khi ghi ngoài RPC.
- RPC: `api.list_class_tests`, `get_test`, `list_test_template_choices`, `create_test`, `update_test`
  (tên/ngày/mô tả), `set_test_show_components`. Mỗi bài có đúng một snapshot cấu hình (`revision = 1`). Mỗi thay đổi ghi `business_entity_versions` + một audit trong cùng transaction;
  nội dung không đổi không tạo phiên bản.
- Quyền tại request: Admin, hoặc User có phân công giáo viên/trợ giảng hiệu lực trong lớp chưa xóa. Lệnh ghi khóa
  tài khoản, lớp (`FOR SHARE`) và phân công rồi kiểm tra lại sau khi chờ. Receptionist bị chặn đọc/ghi (403, A.1
  "không học vụ"); User không có vai trò nhận 404 như lớp không đọc được. Đổi hiện/ẩn chi tiết: chỉ Admin hoặc
  giáo viên; trợ giảng bị 403.
- Chọn template: chỉ template chưa lưu trữ; khóa template (`FOR SHARE`) và yêu cầu phiên bản đã chọn vẫn là
  phiên bản hiện hành, nếu không trả `template_unavailable` (409). Nguồn chỉ là provenance. Sửa/lưu trữ
  template không đổi bài.
- Ngày bài phải nằm trong ngày mở–kết thúc của lớp (`outside_class_dates`).
- API Hono: `GET/POST /v1/classes/:classId/tests`, `GET /v1/classes/:classId/test-templates`,
  `GET/PUT /v1/tests/:id`, `PUT /v1/tests/:id/show-components`; contracts trong
  `packages/contracts/src/assessments.ts`, mã lỗi mới `template_unavailable`.
- UI: tab **Bài kiểm tra** trong trang lớp (workspace Quản trị, hoặc Giảng dạy khi có vai trò trong lớp). Bảng
  bài, menu hàng (sửa thông tin, hiện/ẩn chi tiết) và dialog tạo/sửa thông tin. Bộ soạn
  cấu hình được tách thành `GradingConfigEditor.vue` + `gradingForm.ts` và dùng chung với dialog template.

## Quyết định kỹ thuật và điểm cần xác nhận

- **Ngày bài và khoảng tham gia:** hiện chỉ kiểm tra trong thời gian lớp. Quy tắc "không chuyển ngày ra ngoài
  hợp khoảng tham gia của học sinh đã có kết quả/nhận xét" cần dữ liệu kết quả nên đi cùng feature kết quả.
- **Trợ giảng khởi tạo tùy chọn hiện chi tiết** khi tạo bài (giá trị khởi tạo, theo thiết kế "khởi tạo từ
  template/cấu hình riêng"); sau đó chỉ Admin/giáo viên đổi. Thiết kế ghi "Trợ giảng không đổi tùy chọn
  này", chặt hơn câu TEST-04 ("khi đã có điểm công bố") — **cần người dùng xác nhận** nếu muốn nới cho bài
  chưa công bố.
- Receptionist không đọc được bài kiểm tra (A.1/A.2: không học vụ). Tab ẩn ở workspace Lễ tân.

## Bằng chứng

| Lệnh | Kết quả đã chạy |
| --- | --- |
| `npm run test:db` | 682/682 pgTAP (mới: `tests.test.sql` 70) |
| `npm run test:db:concurrency` | 14/14 (mới: `tests-concurrency.test.ts` 2 — template lưu trữ và phân công kết thúc trong lúc chờ khóa) |
| `npm run test:integration` | 62/62 (mới: `tests.test.ts` 3) |
| `npm run test:unit` | 52/52: contracts 27 (mới 3), API 17, web 8 |
| `npm run lint`, `npm run format:check`, `npm run typecheck` | Đạt |
| `npm run test:e2e -- --workers=2` | 56/56 desktop/mobile (mới: `class-tests.spec.ts` 2 × 2; `test-templates.spec.ts` vẫn đạt sau khi tách bộ soạn) |
| `npm run build`, `npm run check:artifacts` | Đạt; Worker dry-run. Lần này không chạy lại bước đổi tên tạm `template/` |

pgTAP kiểm tra: không lộ bảng/RPC cho client; tạo từ đầu (trim tên, mô tả rỗng → NULL, snapshot chuẩn hóa,
dòng con); thiếu tên/ngày/cấu hình, ngày ngoài lớp, 3 số lẻ; trùng tên được phép; Receptionist 403, User không
phân công 404, giáo viên/trợ giảng đúng cờ quyền; sao chép template có chỉnh, template không bị ghi; sửa/lưu trữ
template không đổi bài, phiên bản cũ/lưu trữ bị từ chối; không có lệnh đổi cấu hình, bài không có snapshot
thứ hai; trợ giảng không bật hiển thị; snapshot/dòng con/bài không sửa-xóa được;
snapshot sai tổng hoặc chữ không mức bị từ chối tại commit; IELTS; kiểm tra commit chạy được với role
`authenticated`; lỗi audit rollback tạo bài; thu hồi phân công chặn phiên cũ; lớp đã xóa chỉ đọc.

## UI và gate còn mở

Đã mở live Metis `products.html` trong trình duyệt tích hợp (card "Product Catalog": tên đậm + dòng phụ nhỏ,
badge nhạt, menu "⋯" cuối hàng) và đối chiếu với trang template đã adapt trước đó; tab mới tái dùng
card/table/RowActionMenu/ModalDialog hiện có. Đã chạy MLedu trên `mledu-dev`, tạo bài theo phần, bật hiện chi
tiết ở 1366×900 (tối), kiểm tra 375×812: không tràn ngang, bảng cuộn trong
khung, modal vừa màn hình. Chưa so pixel-by-pixel với Metis; chưa chụp chế độ sáng/tiếng Anh cho tab mới. Hàng
nút tab của trang lớp xuống dòng trên mobile khi có bốn tab.

Migration đã áp tiến lên `mledu-dev` (không reset) và có một bài thử "Kiểm tra giữa kỳ I" trong lớp Tiếng Anh 9.2
ở dev; `mledu-test` được reset riêng. Chưa chạy CI GitHub/hosted. Không commit, push, deploy hay chạy production
migration.

## Feature kế tiếp

**Đã triển khai 31/10/2026:** [kết quả theo học sinh/bài](gd5-test-results.md), kèm kiểm tra ngày bài theo học sinh đã có kết quả.

Nhập kết quả theo học sinh/bài (TEST-01/04, `test_results` + `component_results`): Vắng riêng, phần chưa nhập
khác 0, tổng do backend tính, danh sách học sinh theo ngày bài giao khoảng tham gia; kiểm tra ngày bài theo
học sinh đã có kết quả. IELTS chi tiết/công bố đi sau.
