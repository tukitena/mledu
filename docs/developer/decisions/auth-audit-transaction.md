# Thử nghiệm ranh giới transaction Auth/audit

Ngày 26/10/2026. Đây là kết quả local của GĐ 0, không phải nghiệm thu toàn bộ Auth.

Đợt thử nghiệm đã đóng theo quyết định chuyển sang GĐ 1; các giới hạn dưới đây
được giữ nguyên và bàn giao trong [biên bản chốt GĐ 0](gd0-closeout.md).

## Quyết định đã thử

Giữ Supabase Auth quản lý mật khẩu và phiên. Dùng Auth Admin API cho ban/unban
và phép thử cấp mật khẩu tạm; PostgreSQL deferred trigger nối thay đổi Auth với
trạng thái/audit MLedu trong cùng transaction của GoTrue.

Các phương án đã cân nhắc:

1. Auth API thành công rồi ghi audit ở request sau: đã đo và không đạt rollback.
2. Auth API + lệnh có ngữ cảnh tin cậy + deferred trigger: chọn cho spike này;
   đã chứng minh rollback trên các thao tác được liệt kê bên dưới.
3. Thay Auth hoặc tự xây reset token: chưa triển khai, chưa cần để kiểm chứng
   hai vấn đề tích hợp ở đây. Recovery gốc vẫn được đo riêng.

## Cách hoạt động

1. API chuyển JWT người thực hiện vào RPC `spike_prepare_auth_command`.
2. RPC kiểm tra phiên hiện hành, loại Admin, tài khoản đích không phải Admin,
   trạng thái và version. Tạo lệnh private có actor/session, target, action,
   request ID, version kỳ vọng và hạn 60 giây. Lệnh không chứa mật khẩu/JWT.
3. Backend gọi Auth Admin API với ban/unban hoặc mật khẩu tạm; chỉ truyền mã
   lệnh trong `app_metadata`. Không tin `user_metadata` do người dùng sửa được.
4. Deferred trigger chạy cuối transaction Auth, sau các câu UPDATE của GoTrue.
   Nó đọc metadata cuối cùng, khóa lệnh, kiểm tra đúng đích/action/version,
   lệnh còn hạn và chưa dùng. Kiểm tra lại actor và phiên; giữ row lock đến commit.
5. Trigger cập nhật trạng thái/cờ mật khẩu và audit chung, rồi tiêu thụ lệnh.
   Audit lỗi hoặc kiểm tra lỗi làm thất bại transaction Auth và rollback tất cả.
6. API đọc kết quả lệnh để xử lý response bị mất hoặc lệnh khóa đồng thời;
   không gọi bù rồi tuyên bố nguyên khối.

SQL không tự ghi mật khẩu/hash, `banned_until` hoặc xóa phiên Auth. GoTrue vẫn
thực hiện các thay đổi Auth qua API. Audit chỉ chứa dữ liệu hồ sơ thử nghiệm,
actor/target/action và command ID; không chép toàn bộ `auth.users` vào audit.

## Kết quả đã đo

Các test nằm tại `apps/api/tests/auth-atomicity.test.ts` và `auth.test.ts`.

| Ca | Kết quả |
| --- | --- |
| Admin cấp mật khẩu tạm qua Auth API | Mật khẩu mới có hiệu lực, phiên cũ mất hiệu lực, cờ phải đổi mật khẩu và đúng một audit cùng commit; actor là Admin thực hiện |
| Audit bị lỗi khi cấp mật khẩu | Auth API trả lỗi; mật khẩu cũ dùng được, mật khẩu mới bị từ chối; cả JWT/RPC và refresh của hai phiên cũ vẫn dùng được; cờ/mốc/metadata và tiêu thụ lệnh rollback |
| Thử lại lệnh sau rollback | Thành công với đúng một audit |
| Ban/unban bị lỗi audit | Native ban và trạng thái MLedu cùng rollback; enable lỗi không làm mất native ban |
| Không có lệnh, lệnh hết hạn/sai đích/sai action/stale version hoặc replay | Auth mutation bị từ chối, không có audit thành công |
| Giả command bằng user metadata | Không cấp được quyền thay đổi mật khẩu |
| Actor đăng xuất trước thực hiện | Không commit được thay đổi Auth |
| Actor đăng xuất lúc mutation đang chờ audit | Đã tái hiện lỗi trước sửa; sau sửa logout chờ transaction đang được phép commit, rồi mới hoàn tất |
| Hai lệnh khóa đồng thời | Một thay đổi, một audit; request còn lại nhận no-op |

Ca đồng thời dùng database lock để điều khiển thứ tự, không dựa vào sleep để đoán
request đã tới đâu. Thứ tự khóa là target không phải Admin → actor Admin → phiên
actor, tránh vòng khóa giữa hai tài khoản Admin qua các thao tác được phép.

## Phạm vi tài khoản và phiên

`spike_private.accounts.auth_controlled=true` bật cơ chế thử nghiệm cho fixture
được quản lý. Fixture baseline native dùng `false` để đo hành vi gốc độc lập.
API từ chối thao tác bridge trên target chưa bật cơ chế; không âm thầm thay Auth
rồi bỏ qua trạng thái/audit ứng dụng. Đây chưa phải quy trình enroll tài khoản
production. Schema này chưa thay ERD chính thức.

Ban native chặn đăng nhập; API/RPC kiểm tra tài khoản và phiên ở request. Access
Token Hook chặn tài khoản disabled và refresh của phiên tạo trước mốc thu hồi,
kể cả sau unban. Phiên active refresh bình thường. Không xóa `auth.sessions`
bằng SQL; các hàng phiên có thể vẫn tồn tại trong Auth dù không còn dùng được
qua những luồng đã kiểm chứng. Chưa nghiệm thu mọi endpoint Auth/Storage/Realtime.

## Giới hạn trước khi dùng production

- Chỉ thử ban/unban và **Admin cấp mật khẩu tạm cho tài khoản không phải Admin**.
  Chưa có route đổi/reset mật khẩu production hoặc luồng tự đổi giữ phiên hiện tại.
- Tài khoản controlled từ chối thay mật khẩu trực tiếp khi thiếu lệnh hợp lệ.
  Chưa nối recovery/self-service vào cơ chế lệnh, nên không coi đây là Auth hoàn chỉnh.
- Việc tham chiếu các cột Auth và thứ tự cập nhật là phụ thuộc nền tảng phải kiểm
  tra khi nâng GoTrue/đổi cấu hình, gồm bảo trì/rehash mật khẩu. Chưa đo hosted.
- Cần nghiệm thu thêm khóa/mở đồng thời với login, thay quyền qua công cụ vận hành,
  lỗi/mất response mạng, dọn lệnh hết hạn và audit retention 60 ngày.
- Kết quả này không sửa lỗi recovery gốc; các gate recovery vẫn đỏ độc lập.

## Cơ sở kỹ thuật

- [PostgreSQL trigger nằm trong transaction của câu lệnh kích hoạt](https://www.postgresql.org/docs/17/trigger-definition.html).
- [Supabase hướng dẫn trigger trên auth.users và lưu ý đối tượng do nền tảng quản lý](https://supabase.com/docs/guides/auth/managing-user-data).
- [GoTrue v2.197.0: Admin update dùng transaction cho password/app_metadata/ban](https://github.com/supabase/auth/blob/v2.197.0/internal/api/admin.go).
- [GoTrue v2.197.0: UpdatePassword thu hồi phiên trong transaction](https://github.com/supabase/auth/blob/v2.197.0/internal/models/user.go).

Phần trigger/lệnh là thiết kế của dự án đã thử local, không phải cam kết của
Supabase rằng mọi quy tắc MLedu tự động được đáp ứng khi bật một cấu hình.
