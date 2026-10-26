# Thử nghiệm Auth/audit — Giai đoạn 0

Ngày: 26/10/2026. **Đã đóng đợt thử nghiệm GĐ 0 và bàn giao sang GĐ 1 theo quyết
định của người dùng.** Gate Auth chưa đạt toàn bộ; recovery đồng thời vẫn chưa
đạt trên local. Xem [biên bản chốt và công việc chuyển tiếp](gd0-closeout.md).

## Phạm vi hiện tại

Supabase Auth thật, Hono API local, fixture giả. Project Docker `mledu` trên cổng
5432x; chưa deploy hosted/production, chưa có Vue. Tiếp tục bản thử nghiệm theo
xác nhận của người dùng; vòng tích hợp dùng migration bổ sung, không reset DB.

Fixture `auth_controlled=true` dùng cơ chế tích hợp mới; fixture baseline native
cố ý đặt `false` để giữ phép đo gốc. Các bảng ở `spike_private`, chưa thay ERD.

## Kết quả hiện tại

| Hạng mục | Kết quả | Phạm vi kết luận |
| --- | --- | --- |
| Native khóa/mở khóa Auth + trạng thái MLedu + audit | Đạt các test local | Ban/unban thực hiện qua Auth Admin API, audit lỗi thì rollback cả Auth và MLedu |
| Phiên khi khóa và sau mở lại | Đạt các test local | Đăng nhập/refresh bị chặn lúc khóa; token cũ bị API/RPC chặn, refresh cũ vẫn bị chặn sau unban; đăng nhập mới dùng được |
| Audit nguyên khối với cấp mật khẩu tạm | Đạt thử nghiệm riêng | Native mật khẩu/thu hồi phiên/cờ phải đổi/audit cùng commit hoặc rollback; chưa phải luồng password production |
| Recovery một lần khi dùng đồng thời | Chưa đạt | Admin-generated POST và link email GET/POST đều tái hiện hai phiên/hai lần đổi trên GoTrue local v2.197.0 |
| Recovery hết hạn 5 phút | Đạt phép đo vòng trước | Link trước hạn dùng được, sau 301 giây thực bị từ chối; vòng này không đổi otp_expiry |

Chi tiết thiết kế, quyền lệnh, lỗi và giới hạn:
[Thử nghiệm transaction Auth/audit](auth-audit-transaction.md).

## Recovery qua email đã xác minh thêm

Vòng đầu dùng `admin.generateLink()` + `verifyOtp()`. Vòng tiếp theo yêu cầu reset
qua `resetPasswordForEmail`, lấy link thực sự gửi đến Mailpit rồi thử:

| Đường xác thực | Số lượt | Kết quả mỗi lượt |
| --- | ---: | --- |
| GET trực tiếp link email, đọc redirect có phiên | 3 | 2 xác thực, 2 session ID khác nhau, 2 cập nhật mật khẩu thành công |
| POST `verifyOtp` với token từ email | 3 | 2 xác thực, 2 session ID khác nhau, 2 cập nhật mật khẩu thành công |

Không bỏ assertion tối đa một lần. Không suy rộng thành lỗi mọi bản hosted,
không tự viết lại reset token. Số đếm đã được lưu trong
[bằng chứng chốt GĐ 0](evidence/gd0-auth-results.json), không chứa token/link/mật khẩu.
Báo cáo ở `tmp/recovery-email-concurrency.json` sẽ được sinh lại khi chạy test.

Giới hạn 60 giây của yêu cầu cấp link mới không bảo đảm serialize hai request
xác thực cùng một link. File local giữ `max_frequency=1s` và quota test; chưa
coi đây là cấu hình production. SMTP local không gửi email ra ngoài.

## Bằng chứng và lệnh chạy lại

- `npm test`: **38 test, 35 đạt, 3 thất bại**, không skip/cancel. Ba test đỏ là
  các gate recovery native: Admin-generated POST, email GET và email POST.
- `npm run test:auth:integration`: chỉ nhóm tích hợp và audit, **26 test** đã đạt
  trong lần chạy toàn bộ ở trên; script riêng giúp chạy lại nhóm này.
- `npm run test:auth:recovery`: hai gate email, mỗi gate có ba lượt thử đồng thời.
- `npm run typecheck`: exit 0 sau bản sửa giữ quyền đến commit.
- `npm run test:auth:expiry`: test chậm riêng, bằng chứng vòng trước 301.309 giây;
  không chạy lại vì không thay cấu hình thời hạn hay thuật toán kiểm tra OTP.
- Log/JSON tạm đã dọn khi chốt GĐ 0. Giữ số liệu trong bằng chứng chốt và test
  nguồn để chạy lại; `npm run local:auth` tạo lại cấu hình kết nối local trước test.

Hướng dẫn môi trường và endpoint: [README](../../../README.md).

Môi trường: Node 24.12.0, npm 11.19.0, Supabase CLI 2.120.0, PostgreSQL 17.11,
GoTrue v2.197.0, Mailpit v1.31.3. Dependency được khóa trong package-lock.json;
không lấy config/dependency từ template/.

## Những gì đã được sửa sau review

- Vòng đầu: phiên tạo trong lúc tài khoản bị khóa không được hồi sinh khi mở lại.
- Vòng này: actor logout có thể chen vào sau kiểm tra quyền nhưng trước commit
  khi audit đang chờ. Đã tái hiện bằng test đỏ với DB lock, giữ actor/session row
  lock qua commit rồi chạy xanh. Test rollback cũng kiểm tra refresh của hai phiên cũ.

## Chưa triển khai hoặc chưa nghiệm thu

Tạo tài khoản nghiệp vụ có audit; AUTH-04/05 xóa mềm/khôi phục và giữ email;
AUTH-08 cấm đổi email ở mọi đường truy cập; tự đổi/reset mật khẩu production;
kiểm tra/hủy phân công khi nâng User → Receptionist (prototype trả 501);
UI/workspace, Workers runtime, audit retention và công cụ vận hành. Chưa thử
hosted, PKCE hoặc mọi endpoint Auth/Storage/Realtime. Avatar và Excel vẫn riêng.

Một số chuyển trạng thái không hợp lệ trong thử nghiệm role còn trả 500 thay vì
409. Nếu tiến trình test bị kill, đối tượng tiêm lỗi có thể còn lại; không chạy
hai suite tiêm lỗi đồng thời. Chỉ reset local khi chắc chắn không có dữ liệu cần giữ.

Công việc recovery chuyển sang G1-01: xác minh trên phiên bản/luồng hosted sẽ dùng,
bao gồm PKCE, trước khi quyết định nâng bản hoặc bổ sung kiểm soát. Việc đóng
đợt thử nghiệm không thay thế điều kiện nghiệm thu còn lại.
