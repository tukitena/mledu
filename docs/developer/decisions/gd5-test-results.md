# GĐ5 — Feature 3: kết quả bài kiểm tra theo học sinh (TEST-01/04/05, TEST-03)

Ngày triển khai/kiểm chứng local: **31/10/2026**. Phạm vi: nhập kết quả **số, phân số, chữ** (trực tiếp hoặc
theo phần) và **Vắng** cho học sinh của bài (TEST-01/04/05); quy trình **TEST-03** khi đổi cấu hình bài đã có
kết quả; quy tắc ngày bài theo học sinh đã có kết quả (TEST-05). Tiếp nối [bài kiểm tra/snapshot](gd5-tests.md).
**Chưa triển khai:** kết quả IELTS, lệnh công bố/hủy công bố (ACAD-01), trang phụ huynh, nhận xét, Excel,
xóa/khôi phục bài (TEST-06). Không đổi đặc tả.

## Hành vi và dữ liệu

- Migration `20261031120000_test_results.sql`: `app.test_results` (một dòng/học sinh/bài, `UNIQUE (student_id,
  test_id)` kể cả dòng đã xóa, FK ghép tới snapshot của chính bài) và `app.component_results` (thiếu dòng = chưa
  nhập, 0 = đã nhập). Đúng thiết kế trong [assessment-schema.md](../assessment-schema.md).
- **Danh sách học sinh** của bài: có lần tham gia trong lớp (kể cả đã kết thúc hoặc hồ sơ đã xóa) giao với ngày
  bài 00:00–24:00 giờ Việt Nam; cộng học sinh đang có kết quả. Học sinh ngoài danh sách bị từ chối khi lưu.
- **Giá trị:** số 0…tối đa, tối đa hai chữ số thập phân (8,255 bị từ chối, không làm tròn); phân số nguyên
  0…tổng; chữ là mã mức `l1…` của snapshot; theo phần chỉ nhận mã `c1…` của snapshot, giới hạn theo từng phần.
  Không ghi đè tổng khi theo phần: DB cộng chính xác (1,25 + 2,10 = 3,35), phân số giữ mẫu số toàn bài (20/90).
  `complete` là giá trị suy ra (Vắng, hoặc đủ mọi phần).
- **Lưu:** `api.save_test_results(test, configId, items)` nhận các dòng đã đổi, mỗi dòng `expectedVersion`
  (`null` = chưa có kết quả đang dùng); `configId` khác snapshot hiện hành → `version_conflict`. Khóa: tài
  khoản → lớp (`FOR SHARE`) → phân công → bài (`FOR SHARE`) → kết quả (`FOR UPDATE`, theo thứ tự học sinh).
  Mỗi kết quả đổi ghi một phiên bản `test_result`; cả lần lưu ghi **một audit** `test_result.save` với
  trước/sau. Nội dung không đổi không ghi gì. `entry: null` xóa kết quả (giữ dòng, nhập lại dùng cùng ID).
- **Khóa công bố:** cột `published_*` có sẵn; kết quả đang công bố không sửa/xóa được (`result_published`).
  Chưa có lệnh công bố nên hiện chỉ kiểm chứng bằng pgTAP đặt cột trực tiếp.
- **TEST-03:** `change_test_config` (khi cấu hình thật sự đổi) bị chặn nếu còn kết quả công bố; ghi phiên bản
  từng kết quả trước khi xóa giá trị/dòng phần hiện hành, chuyển kết quả sang snapshot mới; điểm thành "đã
  xóa" để nhập lại, **Vắng giữ nguyên**; audit `test.change_config` chứa kết quả trước/sau. Không tự công bố.
- **Ngày bài:** `update_test` từ chối ngày mới nằm ngoài mọi lần tham gia của học sinh đang có kết quả
  (`test_date_excludes_results`, `details` = tên học sinh), không tự xóa/hủy công bố. Phần nhận xét sẽ bổ sung
  cùng feature nhận xét.
- **API:** `GET/PUT /v1/tests/:id/results`; contracts `ResultEntry`, `SaveTestResultsRequest`, `TestResults`;
  `ClassTest.resultCount`; mã lỗi mới `result_published`, `test_date_excludes_results`.
- **Quyền:** như ghi bài — Admin hoặc giáo viên/trợ giảng có phân công hiệu lực; Receptionist 403, User không
  vai trò 404; lớp đã xóa chỉ đọc. Trợ giảng được nhập/sửa kết quả chưa công bố (TEST-04).
- **UI:** menu hàng bài có **Nhập kết quả**/**Xem kết quả** mở dialog rộng (cùng mẫu dialog điểm danh): cột Vắng,
  ô từng phần hoặc ô kết quả/danh sách mức, tổng tạm tính ở client chỉ để xem, trạng thái Chưa nhập / Chưa hoàn
  tất / Hoàn tất / Vắng / Chưa lưu / Đã công bố. Giá trị sai được đánh dấu và không gửi. Bảng bài có cột số kết
  quả; dialog đổi cấu hình cảnh báo khi bài đã có kết quả. IELTS hiện thông báo "sẽ có ở bước sau".

## Quyết định kỹ thuật

- Xóa kết quả là xóa mềm theo dòng (`deleted_at/by`, không lý do) để giữ một ID theo học sinh/bài; lịch sử đầy
  đủ nằm ở `business_entity_versions`.
- `expectedVersion = null` chấp nhận dòng đã xóa: client không cần biết phiên bản của kết quả không còn dùng,
  vẫn chặn ghi đè kết quả đang dùng mà người kia vừa nhập.
- Một audit cho cả lần lưu lưới (như điểm danh), mỗi kết quả vẫn có phiên bản nghiệp vụ riêng.

## Bằng chứng

| Lệnh | Kết quả đã chạy |
| --- | --- |
| `npm run test:db` | 752/752 pgTAP (mới: `test_results.test.sql` 70; `tests.test.sql` cập nhật `resultCount`) |
| `npm run test:db:concurrency` | 15/15 (mới: lưu điểm chờ lệnh đổi cấu hình rồi bị từ chối, không tạo kết quả) |
| `npm run test:integration` | 65/65 (mới: `test-results.test.ts` 3) |
| `npm run test:unit` | contracts 29 (mới 2), API 17, web 8 |
| `npm run lint`, `npm run format:check`, `npm run typecheck` | Đạt |
| `npm run test:e2e -- --workers=2` | 58/58 desktop/mobile (mới: `test-results.spec.ts` 1 × 2) |
| `npm run build`, `npm run check:artifacts` | Đạt; không chạy lại bước đổi tên tạm `template/` |

Kiểm tra trực quan trên `mledu-dev` (migration áp tiến, không reset; thêm 4 học sinh mẫu vào lớp Toán 11.2 và bài
"Kiểm tra 15 phút"): nhập 1,25 + 2,1 → 3,35/10 Hoàn tất, Vắng, giá trị 4,5 > 4 bị đánh dấu không gửi, 4 → Chưa hoàn
tất; 1280×800 và 375×812 không tràn ngang trang, bảng cuộn trong dialog. Chưa chụp chế độ sáng/tiếng Anh cho
dialog. Chưa chạy CI GitHub/hosted; không commit, push, deploy hay migration production.

## Footer và chỉnh UI cùng đợt

- Bỏ dòng hint trên bảng tab Bài kiểm tra; nút "Tạo bài kiểm tra" căn phải như tab Nhân sự.
- Footer chung `AppFooter.vue` trong `AppShell` theo mẫu người dùng cung cấp: logo `primary.png`/`primary-dark.png`
  (cắt lề trong suốt bằng CSS) | hai hàng link (không icon) — © năm, "Hướng dẫn sử dụng" (sắp có, chưa bấm
  được), "Hỗ trợ" (mailto); thiết kế bởi, email, điện thoại — trên nền sóng `background.png`/`background-dark.png`.
  Chữ 13px, link gạch chân màu primary; footer chỉ cao vừa logo (12rem, ~130px trên desktop), chữ đè lên sóng. Dùng container query 52rem (theo bề rộng cạnh sidebar): hẹp hơn thì logo
  ở trên, các mục xếp dọc, căn giữa, có đường kẻ. Đã xem sáng/tối 1440×900 và 375×812, không tràn ngang.

## Feature kế tiếp

Công bố/hủy công bố kết quả (ACAD-01): theo học sinh và cả lớp, chỉ Admin/giáo viên, chỉ kết quả hoàn tất hoặc
Vắng, công bố cả lớp trả danh sách thiếu; sau đó IELTS kết quả hoặc nhận xét theo thứ tự GĐ5.
