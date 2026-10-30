# GĐ4 — Lịch thực tế và chuyên cần

Ngày bắt đầu: 30/10/2026. Thực hiện tuần tự trên checkout hiện tại; không tạo branch/worktree,
không commit/push/deploy tự động. Nguồn nghiệp vụ: `plans.md` SCHED-01–06, ATT-01;
ranh giới: `techstack.md` §4.1–4.2; phụ thuộc GĐ3 trong `Implementation-plan.md`.

## Thiết kế

Vue → Hono → một RPC cho mỗi lệnh. Lịch tuần được lưu theo phiên bản ngày áp dụng;
buổi thực tế có định danh ổn định, snapshot vị trí, trạng thái nghỉ/gỡ và lịch sử nghiệp vụ.
Exclusion constraint dùng khoảng [bắt đầu, kết thúc) chống đặt phòng chồng nhau.
Không sinh lịch quá khứ; giữ ngoại lệ khi thay lịch. Các thay đổi hàng loạt có preview và
xác nhận gắn với version; RPC kiểm tra lại toàn bộ điều kiện khi áp dụng.
Nghỉ lễ chỉ Admin; lịch cho manager/giáo viên hiện hành; điểm danh thêm trợ giảng hiện hành.
Điểm danh theo student/session, kiểm tra khoảng tham gia thực tế, lưu cả danh sách và audit
nguyên khối. Không thêm thư viện calendar khi bảng/list và modal hiện có đáp ứng luồng.

Các lựa chọn kỹ thuật do người triển khai quyết định: materialize buổi tới ngày kết thúc lớp
để constraint DB bảo vệ toàn bộ lịch; snapshot phòng/địa điểm của buổi giữ sau đổi danh mục;
preview chạy cùng logic command trong transaction có rollback, xác nhận chạy lại và kiểm tra version.

## Ràng buộc và review focus

- Asia/Ho_Chi_Minh; ngày nghỉ loại trừ từ 00:00; không thay buổi đã bắt đầu.
- Lịch/ngày lễ/điểm danh có business history và audit cùng transaction; không dựa vào audit để phục hồi.
- Chống stale preview, hai lệnh đồng thời và đổi quyền/thu hồi phiên ngay tại request.
- Giữ ngoại lệ, buổi nghỉ và khoảng đóng lớp khi sửa lịch/gia hạn/mở lại.
- Phòng/địa điểm lưu trữ không chọn mới; chặn lưu trữ nếu còn lịch/buổi sử dụng.
- `null` không tính Vắng; buổi cũ dùng lịch sử tham gia, không nhân đôi do thêm lại hồ sơ.
- UI theo Metis Calendar/Add Event và bảng/modal hiện có; desktop/mobile, VI/EN, theme.

## Thứ tự thực hiện

1. [x] Lịch tuần/buổi thực tế, quyền, kiểm tra phòng, preview/confirm, audit/history và hook vòng đời.
   Files: migration scheduling, contracts scheduling, API scheduling; SQL history + concurrency tests.
2. [x] Ngày lễ và cảnh báo nhân sự; ràng buộc phòng/địa điểm và snapshot lịch sử.
   Files: migration scheduling tiếp theo, API/contracts tương ứng; rollback/permission/time tests.
3. [x] Điểm danh và ghi chú theo student/session; phiên bản danh sách, lịch sử và quyền.
   Files: migration attendance, contracts/API attendance; attendance-scope SQL/integration tests.
4. [x] UI lớp: lịch tuần/buổi, nghỉ/bù, preview/xác nhận, nghỉ lễ, điểm danh.
   Files: scheduling/attendance Vue, class detail integration, locales; scheduling E2E.
5. [x] Review, lint/format/typecheck/unit/DB/concurrency/integration/E2E/build/artifacts;
   ghi bằng chứng thực tế vào decisions và cập nhật checkbox chỉ khi đủ bằng chứng.

Mỗi bước: test trước → chạy thấy thất bại vì tính năng thiếu → triển khai → chạy lại.

## Tiến độ / bằng chứng

- Checkout sạch khi bắt đầu. Nền GĐ3 có `on_class_lifecycle` và `assert_room_unused` chưa nối lịch.
- Browser host unavailable; retry theo yêu cầu người dùng đã mở được live Metis trong Edge native.
  Đã xem/chụp Dashboard, Calendar và Add New Event (desktop, cửa sổ 1530×822, zoom 90%).
  Sau đó đã chụp/xem ảnh MLedu desktop/mobile, VI/sáng và EN/tối; live Metis mobile/cùng
  viewport còn thiếu vì người dùng dừng Computer Use bằng Escape. Visual gate vẫn mở.
- CI cũ đã xác minh có run thành công; CI của thay đổi GĐ4 và hosted chưa kiểm chứng;
  gate Auth/audit liên hệ thống vẫn ngoài phạm vi GĐ4.
- Review chỉ đọc độc lập đã thực hiện; các finding Important (Vue Proxy, warning lớp đối
  ứng và sửa phương án mở lại) đã có test tái hiện và sửa. Không có agent ghi song song.
- Bổ sung red→green: nghỉ thủ công qua lễ/đóng lớp, phòng lưu trữ khi mở lại, weekday NULL,
  thu hồi/hết hạn quyền sau chờ khóa, history ON CONFLICT, refetch sau lifecycle và preview
  không bị đổi lớp không liên quan vô hiệu. Mốc revision tương lai vẫn có ưu tiên từ mốc đó;
  test thay pattern phải chọn đúng mốc cần thay, không xóa revision tương lai âm thầm.
- Quyết định: dùng constraint DB cộng mutex cho lệnh lịch/catalog/lifecycle. Scope fingerprint
  đã thu hẹp sau E2E đồng thời tái hiện false conflict (39/40); phép thử mới chứng minh lớp
  không liên quan không vô hiệu preview. Lễ vẫn có scope toàn trung tâm.
- Ba migration đã áp dụng trên test và dev local theo hướng tiến; không reset dev. Các log
  kiểm chứng tạm ở `tmp/gd4-*.log`; bằng chứng lâu dài trong quyết định GĐ4.
- Kiểm chứng cuối: 499 pgTAP, 12 concurrency, 51 integration, 36 unit, 40 E2E đạt;
  lint/format/typecheck/build/artifacts và diff check đạt. Template đã khôi phục sau
  phép thử build không có đường dẫn tham chiếu. Không còn finding Important chưa xử lý;
  chỉ chưa chốt đối chiếu visual đồng viewport và CI/hosted của GĐ4.
