# GĐ3 — Dữ liệu lõi, hồ sơ lớp và lần tham gia

Ngày kiểm chứng: **27/10/2026**, trên Supabase local. Hoàn tất phạm vi dữ liệu lõi của GĐ3;
chưa nghiệm thu toàn bộ CLASS-05 hoặc các xử lý lịch/học phí liên miền ở GĐ4/6/9.

**Bổ sung 29/10/2026:** Quyền User chỉ đọc mô tả trong biên bản lịch sử này đã được
thay bằng quyền sửa theo quyết định 28/10/2026 tại STU-04/STU-03. Xem
[triển khai và bằng chứng quyền sửa](student-edit-permissions.md).

## Phạm vi

Danh mục, hồ sơ học sinh, lớp và phân công đã có trước lần triển khai này. Các bộ kiểm thử
hiện hành được chạy lại cùng phần mới để kiểm tra CAT-01, STU-01–04 và CLASS-01–04.
Lần triển khai này tập trung STU-03, CLASS-04, ảnh hưởng xóa học sinh ở STU-01 và nền CLASS-05.

- Hồ sơ học sinh–lớp chứa nhiều lần tham gia. Học lại giữ hồ sơ cũ; xóa rồi thêm lại tạo ID
  hồ sơ mới, giữ toàn bộ lịch sử hồ sơ cũ. Mọi lần tham gia của hồ sơ mới đều không có hiệu lực
  trước thời điểm xóa hồ sơ trước đó, kể cả nhập ngày hồi tố.
- Ngày vào bất biến; ngày nghỉ chỉ ghi một lần và loại trừ từ 00:00 theo Asia/Ho_Chi_Minh.
  Constraint DB chặn khoảng chồng nhau trong cùng hồ sơ. Hủy đăng ký chưa bắt đầu hoặc
  xóa hồ sơ/học sinh/lớp lưu sự kiện cùng lý do và thời điểm thực tế, không xóa lịch sử.
- Chuyển lớp dùng một RPC: ghi ngày nghỉ nguồn và tham gia đích cùng transaction với audit.
  Lỗi khoảng tham gia ở đích hoặc lỗi audit rollback cả hai phía.
- Đóng/mở/xóa/khôi phục lớp có version, quyền và preview ảnh hưởng. Khôi phục trả lớp về
  Đóng; mở lại/gia hạn không hồi sinh khoảng đã kết thúc. Đã chuẩn bị hook transaction
  cho lịch và học phí; các hook chưa đại diện cho tính năng lịch/học phí đã hoàn thiện.
- Admin/Receptionist thao tác; User chỉ đọc lớp có phân công hiện hành. API/RPC kiểm tra
  phiên, quyền và phạm vi mỗi request; thu hồi phiên/phân công có hiệu lực ở backend.
- UI có tab học sinh của lớp, tìm/chọn học sinh, học lại, ngày nghỉ, ghi chú, hủy, xóa,
  chuyển lớp; lịch sử lớp trong chi tiết học sinh và preview trước xóa học sinh/đóng/xóa lớp.

## Quyết định kỹ thuật

`packages/contracts/src/enrollments.ts` định nghĩa DTO và request schema. Hono đăng ký
routes trong `apps/api/src/modules/enrollments/routes.ts`; mỗi mutation gọi một RPC.
DB types đã được sinh lại từ schema local.

Ba migration theo thứ tự:

1. `20261027140000_enrollments.sql`: hồ sơ, participation, sự kiện vòng đời, API/RPC,
   quyền, lịch sử và audit. Tiếp tục bản nháp đã tồn tại và đã được áp dụng ở local.
2. `20261027140100_enrollment_history_guards.sql`: lịch sử đăng ký đã hủy vẫn khóa ngày
   mở lớp; áp dụng mốc xóa cũ cho mọi lần tham gia của hồ sơ được thêm lại.
3. `20261027140200_enrollment_lock_order.sql`: thống nhất khóa lớp → học sinh → hồ sơ →
   participation. Chuyển lớp khóa hai lớp theo ID; advisory lock theo học sinh tuần tự hóa
   các lệnh tham gia của cùng học sinh, tránh deadlock giữa xóa/sửa và chuyển hai chiều.

Review độc lập chỉ đọc phát hiện hai lỗi đã được sửa và có test tái hiện trước khi sửa:
form Học lại lấy nhầm ngày nghỉ của lần trước; thứ tự khóa đảo chiều khi sửa ghi chú đồng
thời xóa hồ sơ. Test khóa dùng hai kết nối PostgreSQL, đã tái hiện `40P01`; sau sửa, ghi chú
cũ nhận conflict nghiệp vụ `PT409` và không ghi đè lịch sử. Script `test:db:concurrency`
được thêm vào CI sau integration.

Nội dung dịch giữ trong `apps/web/src/locales/vi.ts` và `en.ts`, theo cách tổ chức hiện có.
Hai file `enrollments-vi.ts`/`enrollments-en.ts` tạm tách đã được gộp lại; việc tách file
trước đó chỉ nhằm nhóm nội dung theo tính năng, không đem lại lazy-loading hay lợi ích runtime.

## Bằng chứng kiểm chứng

| Lệnh | Kết quả local |
| --- | --- |
| `npm run lint`, `npm run format:check`, `npm run typecheck` | Đạt |
| `npm run test:unit` | 34/34: contracts 12, API 17, web 5 |
| `npm run test:db` | 350/350 pgTAP; riêng `participation_periods` 72 |
| `npm run test:db:concurrency` | 1/1, sửa ghi chú đồng thời xóa hồ sơ |
| `npm run test:integration` | 47/47; `class-transfer` gồm 7 test, có nhập học đồng thời và chuyển hai chiều cùng học sinh |
| `npm run test:e2e -- --workers=2` | 32/32, desktop và Pixel 7; gồm luồng thêm → nghỉ → học lại → chuyển → hủy → đóng lớp |
| `npm run build` | Đạt khi tạm chuyển `template/` ra khỏi đường dẫn tham chiếu; đã khôi phục thư mục sau kiểm tra. Worker chạy `--dry-run`, không deploy |
| `npm run check:artifacts`, `git diff --check` | Đạt |

Lần chạy E2E toàn bộ với số worker mặc định có 31/32 đạt: test phân công lớp cũ trên mobile
timeout ở menu thao tác tài khoản. Lần chạy toàn bộ với 2 worker đạt 32/32; chưa kết luận
nguyên nhân của timeout đó. Test GĐ3 đạt riêng 2/2 và trong lần chạy toàn bộ.

`command_atomicity.test.sql` trước đây đếm tổng bảng nên lỗi trên DB đã có dữ liệu test.
Đã giới hạn kiểm tra history/audit/outbox vào timestamp của transaction kiểm thử; toàn bộ
pgTAP đạt trên DB đang có dữ liệu mà không cần reset. Đây là cập nhật cho lưu ý chạy lại
trong hồ sơ GĐ2.

Đã xem live Metis Users/bảng/modal, chụp ảnh và đọc source local (MIT) trước khi làm UI.
Giao diện dùng card, bảng cuộn ngang, tab, modal và token sẵn có của MLedu; kiểm tra ảnh
desktop/mobile, Việt/Anh và sáng/tối, sửa khoảng đệm toolbar. Ảnh ứng dụng do E2E lưu trong
`test-results/enrollments-*/`; bảng trên mobile cuộn trong vùng bảng, không tràn cả trang.
Lần chụp lại live Metis để khớp chính xác viewport bị CDP timeout; không coi đây là kiểm chứng
pixel-perfect. Không thêm import hoặc dependency runtime từ `template/`.

## Giới hạn và bước tiếp theo

- GitHub CI và hosted/staging của thay đổi này chưa được kiểm chứng; không suy kết quả
  từ test local. Migration mới chỉ áp dụng local; không reset DB hoặc triển khai production.
- CLASS-05 còn xử lý lịch/buổi tương lai, nghĩa vụ học phí và thông báo ở GĐ4/6/9.
  Tác vụ, Realtime và nghiệm thu liên miền vẫn theo các gate tương ứng.
- Mã học sinh ổn định ở dữ liệu/API; round-trip xuất/nhập Excel thuộc GĐ8.
- Bước kế tiếp: GĐ4, bắt đầu lịch tuần và sinh buổi thực tế, bảo toàn lịch sử và kiểm tra
  xung đột phòng trước khi nối chuyên cần.
