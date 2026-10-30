# GĐ4 — Lịch thực tế, phòng, nghỉ lễ và chuyên cần

Ngày triển khai/kiểm chứng: **30/10/2026**. Phạm vi **SCHED-01–06, ATT-01**, nối phần lịch
của **CLASS-05** vào hooks GĐ3. Không nghiệm thu tài chính, outbox/jobs hoặc toàn bộ vòng đời
liên miền thuộc GĐ6/9. Kế hoạch/ledger: [gd4-plan.md](../gd4-plan.md).

## Hành vi và dữ liệu

- Lịch tuần có các revision bất biến theo ngày áp dụng; materialize buổi tới ngày kết thúc
  lớp để DB kiểm tra toàn bộ đặt phòng. Cùng một ngày áp dụng dùng revision mới nhất;
  revision đã lên lịch ở mốc sau vẫn có hiệu lực từ mốc đó. Không sinh lại quá khứ.
- Buổi thực tế có ID ổn định, lịch gốc, ngoại lệ, buổi bù, nghỉ buổi/lễ và trạng thái gỡ
  do thay lịch/đóng lớp. Snapshot phòng/địa điểm của buổi đã bắt đầu không bị đổi theo
  danh mục. `business_entity_versions` lưu lịch sử độc lập với retention audit.
- Exclusion constraint tại DB dùng khoảng `[bắt đầu, kết thúc)`; hai buổi liền giờ hợp lệ.
  Trùng phòng chặn, trùng giáo viên/trợ giảng cảnh báo và nêu đúng lớp/buổi đối ứng.
  Không chọn phòng vẫn được lưu. Không lưu trữ phòng/địa điểm đang hoặc sẽ được dùng.
- Mọi thay đổi lịch/lễ có preview và xác nhận. Preview chạy chính logic command trong
  subtransaction rồi rollback; không giữ audit, lịch sử hoặc reservation. Apply kiểm tra
  lại fingerprint, quyền, giờ bắt đầu, phòng và ghi nguyên khối. Sequence có thể có khoảng
  trống sau rollback; số revision không phải số lượng command thành công.
- Đóng/xóa gỡ buổi chưa bắt đầu, giữ quá khứ và bản lưu nghiệp vụ. Mở lại có phương án
  chỉnh riêng từng buổi và tùy chọn thay lịch tuần (kể cả các buổi cần sinh sau gia hạn).
  Một RPC mở lớp, sửa phương án, xử lý lịch và ghi một audit `class.reopen` chứa phương án.
  Không tự biến buổi nghỉ thủ công thành buổi học qua chuỗi lễ → đóng/mở → bỏ lễ.
- Chỉ Admin quản lý lễ; lịch thuộc Admin/Receptionist hoặc giáo viên hiện hành. Điểm danh
  thêm trợ giảng hiện hành. Kiểm tra lại assignment sau chờ khóa, dùng thời gian thực và
  khóa assignment; token cũ không cấp quyền sau thu hồi/hết hạn.
- Điểm danh theo **student/session**, danh sách từ khoảng tham gia tại thời điểm buổi.
  Trước lưu là `null`; khi lưu, đánh dấu Vắng và ghi Có mặt cho phần còn lại của danh sách.
  Không lưu thiếu/trùng học sinh, không đưa người ngoài phạm vi vào Vắng, không đặt lại
  `null`. Ghi chú thuần tối đa 1.000 ký tự, lưu lịch sử, chỉ dùng nội bộ.

Ba migration: `20261030100000_scheduling.sql`, `20261030110000_attendance.sql`,
`20261030120000_scheduling_preview_scope.sql`.
Contracts/DTO tại `packages/contracts/src/scheduling.ts`, `attendance.ts`; Hono routes
ở `apps/api/src/modules/scheduling/routes.ts`; DB types sinh từ DB test thực tế.
Không thêm dependency runtime hoặc thay đổi đặc tả.

## Quyết định kỹ thuật và giới hạn

- Dùng scheduling advisory lock trước actor/class/room locks cho lệnh lịch và helper
  quản trị hiện có để tránh race giữa lễ, danh mục và vòng đời lớp. Các lệnh manager được
  tuần tự hóa trong transaction. Chưa có phép đo contention của trung tâm ở GĐ10.
- Fingerprint của lớp gồm lịch lớp, phòng hiện có/được chọn và các lớp/phân công của cùng
  nhân sự. Tạo lớp không liên quan không vô hiệu preview; đổi cùng phòng/nhân sự vẫn kiểm
  tra lại. Preview lễ có phạm vi toàn trung tâm. Chưa đo contention/tải ở quy mô GĐ10.
- Business version của buổi ghi bằng trigger **AFTER**. BEFORE INSERT cũng chạy cho
  proposal bị `ON CONFLICT` loại, nên ghi lịch sử ở BEFORE sẽ tạo lịch sử buổi không tồn tại;
  đã có test tái hiện và sửa.
- Không commit, push, deploy hay chạy production migration. DB test tách biệt `mledu-test`,
  dùng fixture giả; không reset DB phát triển.
- Đã kiểm tra danh sách migration local, sau đó áp dụng đúng ba migration mới theo hướng
  tiến lên `mledu-dev`; CLI xác nhận áp dụng thành công. Không reset hoặc thay seed phát triển.

## Bằng chứng

| Lệnh | Kết quả đã chạy |
| --- | --- |
| `npm run test:db` | 499/499 pgTAP |
| `npm run test:db:concurrency` | 12/12, gồm exclusion đặt phòng và quyền sau chờ khóa |
| `npm run test:integration` | 51/51, Worker runtime + Supabase test thật |
| `npm run test:unit` | 36/36: contracts 14, API 17, web 5 |
| `npm run lint`, `npm run format:check`, `npm run typecheck` | Đạt |
| `npm run test:e2e -- --workers=2` | 40/40 desktop/mobile, gồm lịch tuần, sửa phương án mở lại, điểm danh và preview/hủy lễ |
| `npm run build`, `npm run check:artifacts` | Đạt khi tạm bỏ đường dẫn `template/`, đã khôi phục thư mục; Worker dry-run |
| `git diff --check` | Đạt |

Các test mới nằm ở `schedule_history.test.sql`, `attendance_scope.test.sql`,
`room-concurrency.test.ts`, `scheduling-permissions.test.ts`, integration/E2E `scheduling`.
Đã tái hiện trước sửa: Vue Proxy không clone được, warning chỉ sai lớp đối ứng, trạng thái
nghỉ bị hồi sinh qua lễ/đóng lớp, mở lại dùng phòng lưu trữ, weekday NULL, quyền hết hạn khi
chờ khóa, lịch sử ON CONFLICT và tab không refetch sau đóng/mở lớp.

## UI và các gate còn mở

Đã mở live Metis trong Edge native, xem/chụp Dashboard, Calendar và Add New Event ở cửa sổ
1530×822, zoom 90%. Đã đọc source local `src-modern/calendar.html`, `_calendar.scss` và
license MIT. Adapt card/toolbar, modal Bootstrap lớn (800 CSS px), form ngày/giờ/phòng,
spacing 24 px desktop/16 px mobile và bảng cuộn vào trang chi tiết lớp hiện có; không thêm
calendar library hoặc phụ thuộc build/runtime vào template. Dùng list buổi để thao tác
nghiệp vụ thay cho lưới sự kiện demo.

Đã chụp và xem ảnh ứng dụng desktop 1280×720 và Pixel 7 (viewport 412×839, scale 2.625), Việt/sáng và
Anh/tối, preview lịch, form tuần, ngày lễ và điểm danh. Ảnh E2E ở `test-results/scheduling-*/`. Thao tác và
cuộn bảng chạy trên cả hai viewport; không tràn ngang toàn trang. **Chưa đối chiếu live
Metis ở cùng viewport/mobile, không tuyên bố pixel-perfect**: browser host unavailable,
fallback native mở được; lần kiểm tra responsive sau đó bị người dùng dừng bằng Escape.

Đã đọc GitHub Actions ngày 30/10/2026: workflow CI có các run thành công, mới nhất đã đọc
[40556079673](https://github.com/tukitena/mledu/actions/runs/40556079673) cho commit
`3a6a4460526dc2b52bb28a692fc073ce308d22ed`. HEAD khi triển khai là
`da7bfda016eacf335eca64119a25b7bd673fcbb5`; thay đổi GĐ4 chưa commit nên **chưa có CI cho GĐ4**.
Không suy CI mới từ run cũ. Hosted/staging, gate Auth/audit liên hệ thống và kiểm chứng
visual đồng kích thước vẫn mở. Bước kế tiếp: chốt đối chiếu giao diện GĐ4 ở viewport hẹp.
