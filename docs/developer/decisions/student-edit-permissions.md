# STU-04/STU-03 — Quyền sửa của giáo viên và trợ giảng

Ngày kiểm chứng: **29/10/2026**, theo thay đổi đặc tả ngày 28/10/2026.

## Phạm vi từ diff

Diff đầu lượt gồm `plans.md`, `techstack.md`, `Implementation-plan.md`: quyền sửa
học sinh, template bài kiểm tra/IELTS, Word/biên nhận và các yêu cầu Excel liên quan.
Repo mới có Auth, danh mục, học sinh, lớp/phân công và lần tham gia. Vì vậy lượt này
cập nhật STU-04/STU-03 và bảo toàn giới hạn STU-01/02, CLASS-04; không triển khai sớm
học vụ, tiền, DOCX hoặc Excel.

## Thay đổi

- Migration `20261028100000_student_edit_permissions.sql` tách quyền sửa khỏi
  `require_manager`. User có phân công giáo viên/trợ giảng hiện hành được sửa hồ sơ
  tổng khi có ít nhất một hồ sơ lớp chưa xóa thuộc lớp chưa xóa được phân công.
- Ghi chú/ngày nghỉ lần đầu phải thuộc đúng lớp. Không mở quyền tạo học sinh, thêm
  vào lớp, học lại, xóa, hủy, khôi phục hoặc chuyển lớp. Hồ sơ tổng đã xóa chặn cả
  sửa lần tham gia; áp dụng cho manager và User.
- Giữ thứ tự khóa lớp → học sinh → hồ sơ → lần tham gia; khóa và kiểm tra lại
  phân công sau khi chờ. `clock_timestamp()` kiểm tra quyền tại thời điểm ghi,
  tránh dùng thời gian đầu transaction khi phân công đã hết hiệu lực trong lúc chờ.
- Ba RPC sửa giữ validation/chống trùng, version, ngày bất biến, lịch sử và audit
  cùng transaction. API Hono hiện có đã chuyển tiếp JWT và gọi một RPC nên không
  cần thêm tuyến ghi hoặc thay middleware.
- DTO `Student` và `ClassStudent` có `canEdit`. UI tách menu Sửa/ghi chú/ngày nghỉ
  khỏi thao tác quản trị; có giải thích Việt/Anh rằng hồ sơ tổng dùng chung ở mọi lớp.
- Điều chỉnh một test Auth cũ: tìm tài khoản vừa tạo bằng email trước assertion,
  vì danh sách phân trang và fixture tích lũy có thể đẩy bản ghi khỏi trang đầu.
  Không đổi hành vi sản phẩm Auth.

## Kiểm chứng

| Lệnh / kiểm tra | Kết quả thực tế |
| --- | --- |
| `npm run test:db` | 417/417 pgTAP, gồm 67 ca mới |
| `npm run test:integration` | 49/49, gồm hai luồng mới cho teacher/assistant |
| `npm run test:db:concurrency` | 7/7, PostgreSQL nhiều kết nối thật |
| `npm run test:e2e -- --workers=2` | 36/36, desktop và Pixel 7 |
| `npm run test:unit` | 34/34: contracts 12, API 17, web 5 |
| `npm run lint`, `npm run typecheck`, `npm run format:check` | Đạt |
| `npm run build` | Đạt khi tạm đưa `template/` sang vị trí khác trong workspace; đã khôi phục |
| `npm run check:artifacts` | Đạt, không có secret hoặc đường dẫn template trong output |
| `npm run test:db:types` | Sinh lại từ test DB, không tạo diff |
| `git diff --check` | Đạt |

Test DB mới đã chạy trước migration: 32/54 ca thất bại do quyền cũ/thiếu capability.
E2E mới trước sửa UI thất bại vì không có menu Sửa; sau sửa, các luồng đạt.
Ca phân công tương lai dùng ngày `Asia/Ho_Chi_Minh`, tránh nhầm ngày UTC khi chạy qua
00:00 giờ Việt Nam. Không tăng timeout để che lỗi selector hoặc dữ liệu phân trang.

Đã kiểm tra ngoài phạm vi, cùng học sinh ở lớp khác, hồ sơ/lớp lưu trữ, lớp đóng,
thu hồi/hết hạn/phân công tương lai, tài khoản bị khóa, phiên bị thu hồi, các lệnh
quản trị trái quyền, khóa ngày, chống trùng và ghi đồng thời cùng version. Kiểm thử
audit lỗi chứng minh rollback tên, liên hệ, ghi chú, ngày nghỉ, version và lịch sử.
Các ca nhiều kết nối giữ lệnh sửa chờ khóa, thu hồi phân công hoặc cho khoảng hiệu
lực đi qua mốc kết thúc rồi thả khóa; cả ba lệnh sửa bị từ chối và không ghi dữ liệu.
Mốc thời gian được điều khiển trên fixture test, không thay đồng hồ hệ thống.

Review độc lập chỉ đọc không phát hiện lỗi chặn. Hai khoảng trống review nêu ra
(hết hiệu lực khi chờ khóa; audit rollback tên/liên hệ) đã được bổ sung kiểm thử đạt.

## Giao diện và ảnh

Đã mở live Metis `users.html`, xem bảng và modal Add New User, chụp desktop/narrow
trước sửa UI; xem markup tại `template/metis-v1.0.0/src-modern/users.html` và license.
Giữ các form/menu MLedu hiện có; chỉ thay quyền hiện thao tác và thêm đoạn giải thích
theo mẫu văn bản phụ. Modal MLedu giữ rộng 500 px và cuộn nội dung; không chuyển sang
modal-lg 800 px của demo. Các trường và nội dung theo nghiệp vụ MLedu.

Đã chụp và xem ảnh app ở **1280×720** và **412×839 CSS px** (Pixel 7), gồm form
Việt/sáng, menu lần tham gia sau khi ghi ngày nghỉ và menu chỉ xem Anh/tối sau thu hồi.
Không thấy tràn trang hoặc mất nút thao tác; bảng mobile cuộn ngang. Ảnh sinh lại qua
`tests/e2e/student-edit-permissions.spec.ts`, tên `shared-profile-light-vi.png`,
`participation-edit-menu.png`, `revoked-edit-dark-en.png`; bản tạm ở
`tmp/student-permissions-evidence/`.

Ảnh live Metis trước sửa dùng viewport Edge có zoom nên không phải đối chiếu pixel
1:1. Khi kiểm tra cuối, browser access host không còn khả dụng; không tuyên bố đã
chụp lại live ở đúng viewport app hoặc đạt pixel-perfect. Hình thức form/menu giữ
theo các component đã có, không thêm phong cách mới.

## Trạng thái triển khai và bước tiếp theo

- Migration đã áp dụng trên `mledu-test` và `mledu-dev` bằng `migration up --local`;
  đã kiểm tra migration list. Không reset/reseed dev hoặc chạy test tự động trên dev.
- Chưa commit/push/deploy. GitHub CI và hosted/staging chưa được kiểm chứng. Khi
  triển khai ngoài local, áp migration trước phiên bản UI/contracts đòi `canEdit`.
- XLS-01/02 vẫn cần quyền tương tự ở preview/apply khi làm GĐ8. Các yêu cầu IELTS
  và DOCX/biên nhận trong diff thuộc GĐ5/6/9, chưa có chức năng để cập nhật ở lượt này.
- Bước phát triển tiếp theo: lịch tuần và sinh buổi thực tế ở GĐ4, theo các gate
  phụ thuộc hiện hành; không coi các gate CI/hosted đã đóng từ kết quả local.
