# GĐ5 — Feature 1: thư viện template bài kiểm tra (TEST-02)

Ngày triển khai/kiểm chứng local: **31/10/2026**. Phạm vi: **TEST-02** và phần cấu hình có kiểu của
**TEST-01/04** dùng trong template. Đây là feature đầu tiên của GĐ5 theo thứ tự trong
[thiết kế học vụ](../assessment-schema.md); bài kiểm tra, snapshot cấu hình, kết quả, IELTS tính điểm,
công bố (ACAD-01) và nhận xét (COMMENT-01–03) **chưa triển khai**. Không đổi đặc tả.

## Hành vi và dữ liệu

- Migration `20261031100000_test_templates.sql`: `app.test_templates` (gốc ổn định, xóa mềm) và
  `app.test_template_versions` (phiên bản bất biến, chặn UPDATE/DELETE/TRUNCATE bằng trigger). FK con
  trỏ phiên bản hiện hành `DEFERRABLE INITIALLY DEFERRED`; RLS bật, không grant bảng cho client.
- Cấu hình JSONB schema v1 được kiểm tra tại DB bởi `app_private.test_template_config` và CHECK chỉ
  nhận dạng đã chuẩn hóa. Số: trực tiếp hoặc 1–50 phần, điểm dương tối đa 2 số lẻ (từ chối, không làm
  tròn), tổng do backend tính. Phân số: số câu nguyên dương, tổng theo phần. Chữ: 1–20 mức, nhãn
  1–100 ký tự, duy nhất theo `name_key`. IELTS: 1–4 kỹ năng L/R/W/S không trùng, mode riêng; L/R chi
  tiết bắt buộc số câu tối đa, W/S không có cấu hình tiêu chí/trọng số; `formulaVersion` do backend gắn
  `mledu-ielts-v1`, từ chối giá trị khác. Mã phần/mức gán theo vị trí (`c1…`, `l1…`). Khóa lạ bị từ chối.
- RPC `api.list_test_templates`, `list_test_template_versions`, `create/update/archive/restore_test_template`:
  chỉ Admin hiện hành (đọc lại loại tài khoản/phiên tại request). Sửa khóa gốc, kiểm tra
  `expectedVersion`, thêm phiên bản mới và đổi con trỏ; lưu nội dung không đổi không tạo phiên bản.
  Mỗi thay đổi ghi `business_entity_versions` + một audit trong cùng transaction. Khôi phục dùng lại ID và
  phiên bản hiện hành cũ.
- API Hono `/v1/test-templates` (GET, GET `/:id/versions`, POST, PUT `/:id`, POST `/:id/archive|restore`);
  contracts `packages/contracts/src/assessments.ts` phản chiếu validator DB để trả lỗi theo trường.
- UI Admin `/admin/test-templates` (menu chỉ ở workspace Quản trị): bảng, lọc loại/tìm không dấu, sửa,
  lịch sử phiên bản, lưu trữ/khôi phục có lý do. Form theo từng loại; nhập 8,25 hoặc 8.25.

## Quyết định kỹ thuật và điểm cần xác nhận

- **Bộ mức chữ mặc định** Chưa đạt/Đạt/Tốt/Xuất sắc được **điền sẵn khi tạo template chữ** (hằng
  `DEFAULT_LETTER_LEVELS`), Admin lưu như template thường có audit. Không seed template hệ thống trong
  migration vì `created_by` cần một Admin thật và môi trường mới chưa có tài khoản. Thiết kế học vụ ghi
  "khởi tạo bằng thao tác hệ thống có provenance"; nếu cần bản ghi mặc định sẵn có thì bổ sung bằng công cụ
  vận hành có audit — **cần người dùng xác nhận**.
- Đọc/chọn template cho giáo viên/trợ giảng theo lớp đích **chưa mở**: feature này chỉ cho Admin đọc. Quyền
  đọc theo phân công sẽ thêm cùng feature tạo bài (TEST-05), kiểm tra lớp đích và chỉ trả template chưa xóa.
- `showComponents` của IELTS bị chuẩn hóa thành `false` khi không có kỹ năng chi tiết.
- Không đặt unique tên template (đặc tả không yêu cầu); phân biệt bằng ID/phiên bản.

## Bằng chứng

| Lệnh | Kết quả đã chạy |
| --- | --- |
| `npm run test:db` | 612/612 pgTAP (mới: `test_templates.test.sql` 67) |
| `npm run test:db:concurrency` | 12/12 |
| `npm run test:integration` | 59/59 (mới: `test-templates.test.ts` 5, gồm hai lần sửa đồng thời chỉ một thành công) |
| `npm run test:unit` | 49/49: contracts 24 (mới 6), API 17, web 8 |
| `npm run lint`, `npm run format:check`, `npm run typecheck` | Đạt |
| `npm run test:e2e -- --workers=2` | 52/52 desktop/mobile (mới: `test-templates.spec.ts` 3 × 2) |
| `npm run build`, `npm run check:artifacts` | Đạt, kể cả khi tạm đổi tên `template/` (đã khôi phục); Worker dry-run |

pgTAP kiểm tra: quyền bảng/RPC, biên 2 số lẻ/0/kiểu chuỗi, 50/51 phần, 20/21 mức, tổng sai, mã sai vị
trí, khóa nhánh khác, IELTS (thứ tự, trùng, thiếu/thừa số câu, công thức khác, trọng số tùy biến), idempotent
chuẩn hóa; Receptionist/User bị chặn; version conflict; không đổi → không tạo phiên bản; v1 giữ cấu hình cũ;
phiên bản không sửa/xóa được; lỗi audit rollback cả tạo và sửa; đổi loại tài khoản làm phiên cũ mất quyền.

## UI và gate còn mở

Đã mở live Metis (`preview.themewagon.com/metis`) trong trình duyệt tích hợp ở viewport 1366×900:
`products.html` (card "Product Catalog", bảng, badge, menu hàng; modal "Add New Product" `modal-lg` 800 px,
lưới `row g-3`, padding 16 px) và `forms.html` (`input-group`, `form-switch` nhãn đậm + mô tả nhỏ). Đã đo
computed style (font 14 px, padding ô 10/12 px, bo 8 px). Trang mới tái dùng card/table/RowActionMenu/ModalDialog
hiện có của MLedu (đã adapt từ Metis). Đã chụp và tự so sánh: desktop sáng 1366×900, mobile 375×812 tối
(không tràn ngang, bảng cuộn trong khung), modal số theo phần/IELTS. Chưa đặt cạnh nhau pixel-by-pixel với
Metis; không tuyên bố khớp tuyệt đối. Ô chọn chế độ IELTS trên mobile bị cắt chữ dài.

Chưa chạy CI GitHub/hosted. Không commit, push, deploy hay chạy production migration. Migration đã áp tiến
lên `mledu-dev` (không reset); `mledu-test` được reset riêng cho kiểm thử.

## Feature kế tiếp

Tạo bài kiểm tra trong lớp (TEST-05) với snapshot cấu hình `test_config_versions` + bảng mức/phần/kỹ năng,
tạo từ đầu hoặc sao chép phiên bản template (khóa template, kiểm tra chưa xóa), quyền Admin/giáo viên/trợ giảng
có phân công hiệu lực, audit nguyên khối. Kết quả/IELTS/công bố đi sau.
