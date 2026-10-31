# GĐ5 — Feature 4–7: công bố, IELTS, nhận xét, xóa/khôi phục bài

Ngày triển khai/kiểm chứng local: **31/10/2026**. Tiếp nối [kết quả theo học sinh](gd5-test-results.md). Bốn
feature làm tuần tự, mỗi feature một migration. Phạm vi: **ACAD-01** (công bố điểm và nhận xét), **TEST-01**
(phần IELTS), **COMMENT-01–03**, **TEST-06**, cùng bổ sung **TEST-05** (ngày bài không loại học sinh đã có nhận
xét). Không đổi đặc tả. Trang phụ huynh (lọc theo công bố/hiện chi tiết) thuộc GĐ7; Excel thuộc GĐ8.

## Feature 4 — Công bố/hủy công bố điểm (`20261031130000_result_publication.sql`)

- `api.publish_test_results(test, student | null, publish)`: một học sinh hoặc cả lớp của **một bài**. Chỉ Admin
  hoặc giáo viên có phân công hiệu lực (`can_publish`); trợ giảng/Lễ tân 403.
- Chỉ công bố kết quả hoàn tất hoặc Vắng; một học sinh chưa đủ → `result_incomplete`. Cả lớp: bỏ qua học sinh thiếu
  và trả danh sách `missing`; không có ai đủ điều kiện (và chưa ai đã công bố) → `nothing_eligible`, không ghi gì.
  Nhập bổ sung sau đó không tự công bố.
- Mỗi kết quả đổi trạng thái tăng `row_version` (lưới cũ sẽ `version_conflict`) và có phiên bản nghiệp vụ; một
  audit `test_result.publish|unpublish` mỗi lệnh. Khóa: bài `FOR SHARE` → kết quả `FOR UPDATE` theo học sinh, cùng
  thứ tự với lưu điểm.
- DTO: `publishedAt/publishedByName`, `ClassTest.publishedCount`, `TestResults.canPublish`.
- UI: cột Công bố trong dialog kết quả (nút theo dòng chỉ với kết quả hoàn tất/Vắng), nút Công bố/Hủy công bố cả
  lớp ở footer, thông báo số đã đổi và học sinh còn thiếu. Bắt lưu thay đổi trước khi công bố.

## Feature 5 — Kết quả IELTS (`20261031140000_ielts_results.sql`)

- Bảng `ielts_skill_results` và `ielts_criterion_results` đúng [thiết kế](../assessment-schema.md), thêm
  `test_results.overall_band`. Thiếu dòng = chưa nhập, không bao giờ là 0.
- Đầu vào `{absent:false, skills:{L:{correctAnswers, band}, R:{band}, W:{criteria}, S:{criteria}}}` theo chế độ của
  snapshot; band 0–9 bước 0,5, sai bước/miền bị từ chối, không sửa. L/R chi tiết giữ nguyên số câu và band người
  dùng nhập, không quy đổi. W/S chi tiết không nhận band; mã tiêu chí theo `formula_version` (`mledu-ielts-v1`).
- Backend tính `roundBand(x) = floor(2x+0,5)/2`: Task 1/Task 2 làm tròn trước, Writing = roundBand((T1 + 2·T2)/3);
  Speaking = roundBand(trung bình 4 tiêu chí); Overall chỉ khi bài có đủ 4 kỹ năng và đủ 4 band. Client gửi
  `overallBand` hoặc band W/S chi tiết bị từ chối.
- Hoàn tất: mọi kỹ năng đã chọn đủ dữ liệu theo chế độ (L/R chi tiết cần cả số câu và band). Bài 1–3 kỹ năng công
  bố được không có Overall; bài 4 kỹ năng thiếu một kỹ năng không công bố được.
- Cùng lệnh `save_test_results` (khóa, phiên bản, một audit). Trigger `test_results_clear_ielts` xóa đầu vào IELTS
  hiện hành khi xóa kết quả hoặc chuyển Vắng; lịch sử đã ghi trước đó.
- UI: một ô mỗi kỹ năng; Writing hai hàng T1/T2 × 4 tiêu chí, Speaking 4 tiêu chí, kèm xem trước "T1 · T2 → band"
  và cột Overall khi đủ 4 kỹ năng. Xem trước dùng cùng công thức (`roundBand` trong contracts), backend là nguồn đúng.

## Feature 6 — Nhận xét và đợt nhận xét (`20261031150000_comments.sql`)

- `app.comment_batches` (chỉ tên, cho trùng, xóa mềm có lý do) và `app.comments` (một dòng/học sinh/bài hoặc
  học sinh/đợt, `UNIQUE` kể cả đã xóa nội dung; văn bản thuần NFC, 1–1.000 ký tự, không tự cắt).
- `commented_at`: thời điểm nội dung hiện hành được viết lần đầu — giữ khi sửa, đặt lại khi viết lại sau khi xóa.
  Đây là mốc lọc lịch sử của COMMENT-02; đợt không có trường ngày.
- Danh sách học sinh: bài → tham gia vào ngày bài; đợt → đang tham gia tại thời điểm hiện tại (hồ sơ lớp chưa xóa);
  cộng học sinh đang có nhận xét. Ngoài danh sách bị từ chối khi lưu.
- RPC: `list/create/update/archive/restore_comment_batch`, `get_comments`, `save_comments`, `publish_comments`
  (đích `test` | `batch`). Nhập/sửa: Admin, giáo viên, trợ giảng; công bố, xóa/khôi phục đợt: Admin hoặc giáo
  viên. Nhận xét đã công bố khóa sửa/xóa (`comment_published`). Công bố nhận xét độc lập với điểm, học sinh khác và
  bài/đợt khác. Xóa đợt tự hủy công bố toàn bộ nhận xét của đợt trong cùng transaction (trạng thái trước nằm trong
  phiên bản), khôi phục dùng lại ID, tất cả chưa công bố.
- Ngày bài (TEST-05): `check_result_participation` nay xét cả học sinh có nhận xét gắn bài.
- API `/v1/classes/:id/comment-batches`, `/v1/comment-batches/:id[/archive|/restore]`,
  `/v1/comments/:kind/:id[/publication]`; contracts `packages/contracts/src/comments.ts`.
- UI: tab **Nhận xét** trong trang lớp (bảng đợt, tạo/đổi tên, xóa có hiển thị ảnh hưởng + lý do, hiện đợt đã xóa
  và khôi phục); menu bài có **Nhận xét**; dialog chung cho bài/đợt với textarea, bộ đếm `n/1000`, trạng thái và
  công bố theo dòng/cả lớp.

## Feature 7 — Xóa/khôi phục bài (`20261031160000_test_archive.sql`)

- `api.archive_test(id, reason, expectedVersion)`, `api.restore_test(id, expectedVersion)`: chỉ Admin hoặc giáo
  viên. Xóa: khóa bài `FOR UPDATE` (chờ lưu/công bố đang chạy), hủy công bố mọi điểm và nhận xét gắn bài (ghi phiên
  bản với trạng thái trước), lưu trữ bài có lý do, một audit `test.archive` liệt kê nội dung đã hủy công bố. Giữ
  điểm, phần, Vắng, IELTS, nhận xét. Khôi phục: cùng ID, mọi nội dung chưa công bố.
- `list_class_tests(class, includeArchived)` (đổi chữ ký, thêm `canArchive`); DTO bài thêm
  `publishedCommentCount`, `deletedAt`, `deletedReason` để hiển thị ảnh hưởng trước khi xác nhận.
- Bài đã xóa: chỉ đọc lịch sử; nhập điểm/nhận xét, công bố bị từ chối (`invalid_state`).
- UI: công tắc **Hiện bài đã xóa**, hành động Xóa bài (dialog ảnh hưởng + lý do) và Khôi phục.

## Quyết định kỹ thuật cần biết

- Một học sinh không có kết quả: công bố đơn lẻ trả `result_incomplete`; nhận xét không có nội dung trả
  `nothing_eligible`.
- Công bố không đổi `updated_at/updated_by` (người sửa nội dung cuối) mà ghi `published_by/at`.
- Nhận xét theo đợt chỉ nhập cho học sinh đang tham gia tại thời điểm nhập (hoặc đã có nhận xét); không cho viết
  mới cho học sinh đã nghỉ, để mốc `commented_at` luôn nằm trong khoảng tham gia. **Cần người dùng xác nhận** nếu
  muốn cho viết nhận xét đợt cho học sinh vừa nghỉ.
- Không có thông báo bắt buộc cho công bố (NOTIF-01 không liệt kê) nên không ghi outbox.

## Bằng chứng

| Lệnh | Kết quả đã chạy |
| --- | --- |
| `npm run test:db` | 938/938 pgTAP (mới: `publication_lock.test.sql`, `ielts_results.test.sql`, `comments.test.sql`, `test_archive.test.sql`) |
| `npm run test:db:concurrency` | 16/16 (mới: công bố chờ lệnh xóa bài rồi bị từ chối) |
| `npm run test:integration` | 70/70 (mới: công bố trong `test-results.test.ts`; `comments.test.ts` 4) |
| `npm run test:unit` | contracts 31, API 17, web 12 (mới: IELTS contracts, `ieltsEntry.test.ts`) |
| `npm run lint`, `npm run format:check`, `npm run typecheck` | Đạt |
| `npm run test:e2e -- --workers=2` | 62/62 desktop/mobile (mới: công bố + IELTS trong `test-results.spec.ts`, `comments.spec.ts`) |
| `npm run build`, `npm run check:artifacts` | Đạt; không chạy lại bước đổi tên tạm `template/` |

pgTAP phủ: quyền (Lễ tân/trợ giảng/phân công bị thu hồi), chỉ công bố hoàn tất/Vắng, danh sách thiếu, không công bố
được bài khác, khóa sửa/xóa/chuyển Vắng khi công bố, đổi hiện chi tiết vẫn được; IELTS
6,125/6,25/6,75, Task 1:2 = 6,5, L/R giữ nguyên, thiếu tiêu chí khác 0, không Overall ở bài 2 kỹ năng, 14 đầu vào sai;
1.000/1.001 ký tự, HTML giữ dạng văn bản, công bố điểm không đổi nhận xét và ngược lại; xóa đợt/bài tự hủy công bố,
khôi phục chưa công bố, cùng ID; lỗi audit rollback mọi lệnh mới.

## UI và gate còn mở

Đã mở live Metis `forms.html` (textarea `form-control` 14 px, padding 7/12 px, bo 6 px) và tái dùng mẫu card/bảng/
RowActionMenu/ModalDialog đã adapt từ `products.html`. Migration áp tiến lên `mledu-dev` (không reset); đã mở dialog
kết quả lớp Toán 11.2 (cột Công bố chỉ ở dòng hoàn tất/Vắng) và tab Nhận xét ở 375×812: không tràn ngang. Pane trình
duyệt hẹp nên chưa chụp đầy đủ 1366×900, chưa đặt cạnh Metis pixel-by-pixel, chưa chụp sáng/tối/tiếng Anh cho các
màn mới. Hàng 5 tab của trang lớp xuống hai dòng trên mobile. Chưa chạy CI GitHub/hosted; không commit, push,
deploy hay migration production.

## Còn lại của GĐ5

Gate dự kiến `grading-config.test.sql` / `tests/e2e/academics.spec.ts` được phủ bởi các file hiện có
(`tests.test.sql`, `test_results.test.sql`, `publication_lock.test.sql`, `ielts_results.test.sql`, `comments.test.sql`,
`test_archive.test.sql`, `test-results.spec.ts`, `comments.spec.ts`) — tên file khác dự kiến. Gate CI/hosted và đối
chiếu visual vẫn mở như các giai đoạn trước. Feature kế tiếp theo kế hoạch: **GĐ6 — học phí** (FEE-01…).
