# MLedu — Tech stack đã chốt và dự toán vận hành

Ngày ghi nhận và đối chiếu giá: **26/10/2026**.

Tài liệu này ghi lại lựa chọn kỹ thuật đã được chấp nhận trong trao đổi. [plans.md](plans.md) tiếp tục là nguồn đặc tả nghiệp vụ hiện hành; tài liệu này không thay đổi quyền, quy tắc dữ liệu hoặc tiêu chí nghiệm thu trong đó. Giá và giả định chi phí ở phần cuối là dự toán, không phải cam kết tải hoặc quyết định mua dịch vụ.

## 1. Kiến trúc đã chốt

**Vue 3 + TypeScript + Vite → Cloudflare Pages; Cloudflare Workers + Hono → Supabase Auth, PostgreSQL, Storage, Realtime và Cron.**

| Lớp | Công nghệ | Trách nhiệm |
| --- | --- | --- |
| Frontend | Vue 3, TypeScript, Vite, Vue Router | SPA cho các workspace nội bộ và trang phụ huynh; route, component và trạng thái giao diện. |
| Giao diện | Bootstrap 5, SCSS, Bootstrap Icons | Xây dựng giao diện trong source chính thức, tham khảo hình thức của Metis. |
| Hosting web | Cloudflare Pages | Build và phục vụ tài nguyên tĩnh của SPA. |
| API | Cloudflare Workers, Hono, TypeScript | Kiểm tra đầu vào, xác thực yêu cầu, API phụ huynh, điều phối nhập Excel và các thao tác cần quyền backend. |
| Xác thực | Supabase Auth | Đăng nhập email/mật khẩu, phiên và khôi phục mật khẩu; bổ sung kiểm tra để đáp ứng chính xác AUTH-01 đến AUTH-08. |
| Dữ liệu | PostgreSQL do Supabase quản lý | Dữ liệu quan hệ, RLS, constraint, khóa và transaction. Dùng phiên bản PostgreSQL được Supabase hỗ trợ tại lúc tạo project. |
| Giao dịch nghiệp vụ | PostgreSQL functions, gọi qua RPC | Thực hiện nguyên khối các lệnh thu/gỡ thu, chuyển lớp, đóng/mở lớp, nhập Excel và audit liên quan. |
| File | Supabase Storage | Ảnh hồ sơ và file nhập tạm; bucket private và quyền đọc/ghi theo nghiệp vụ. |
| Cập nhật trực tiếp | Supabase Realtime | Báo có thay đổi để SPA tải lại thông báo, số chưa đọc hoặc dữ liệu theo quyền hiện hành. |
| Tác vụ | Supabase Cron, bảng job/outbox | Sinh nghĩa vụ học phí, chạy bù, phân phối thông báo, thử lại và dọn audit/thông báo hết hạn. |
| Email | SMTP riêng kết nối Supabase Auth | Email đặt lại mật khẩu; nhà cung cấp cụ thể chưa chốt. |
| Kiểm thử | Kiểm thử PostgreSQL/RLS, API và trình duyệt | Kiểm tra nghiệp vụ, quyền, giao dịch đồng thời và thao tác trên điện thoại/máy tính. Bộ công cụ cụ thể chọn khi khởi tạo dự án. |

Lựa chọn backend chính là **Workers + Supabase**. Supabase Edge Functions là phương án thay thế lớp API để so sánh, không triển khai song song mặc định. Hono hỗ trợ [Workers](https://hono.dev/docs/getting-started/cloudflare-workers); Supabase cung cấp [database functions/RPC](https://supabase.com/docs/guides/database/functions).

Lộ trình và cấu trúc thư mục đề xuất được mô tả tại [kế hoạch triển khai MLedu](../superpowers/plans/2026-10-26-trien-khai-mledu.md). Đây là đề xuất tổ chức triển khai; repository hiện chưa có source ứng dụng hoặc migration đã chạy.

### 1.1. Ranh giới giao tiếp frontend

| Luồng | Đường đi |
| --- | --- |
| Đọc/ghi nghiệp vụ nội bộ và tra cứu phụ huynh | Vue → Workers/Hono → PostgreSQL/RPC. |
| Đăng nhập và refresh phiên thông thường | Vue dùng Supabase Auth SDK; khi gọi API gửi JWT để backend kiểm tra phiên, trạng thái và quyền hiện hành. |
| Quản trị tài khoản, đổi/đặt lại mật khẩu và thao tác xác thực cần audit | Theo luồng backend được thiết kế và kiểm chứng cho AUTH-01–08; không dùng lời gọi SDK trực tiếp để bỏ qua kiểm tra/audit. |
| Realtime | Vue kết nối kênh được cấp quyền để nhận tín hiệu thay đổi tối thiểu, sau đó lấy dữ liệu mới qua API. |
| Truyền file | API cấp quyền cho đúng đường dẫn; trình duyệt có thể truyền trực tiếp tới Storage bằng quyền/URL được cấp. Bước kiểm tra và xác nhận cập nhật nghiệp vụ vẫn qua API. |

Không dùng việc frontend có publishable key làm lý do mở quyền đọc/ghi rộng các bảng hoặc RPC. Quyền truy cập trực tiếp ngoài API vẫn phải được thu hẹp và kiểm thử theo mục 4.1–4.3.

## 2. Quy định về Metis và thư mục tham khảo

**Metis chỉ là template tham khảo. Không lấy Metis làm bộ khung source code của dự án.**

- Đường dẫn dự kiến trong dự án là **`template/`**, được đưa vào `.gitignore` bằng quy tắc `/template/` khi khởi tạo dự án.
- `template/` không tham gia tổ chức source code, workspace/package, dependency graph, TypeScript project, routing, build, lint, test, CI/CD hoặc artifact deploy.
- Source chính thức không import, alias, symlink, đọc lúc runtime hoặc dùng script lấy tài nguyên tự động từ `template/`.
- Không dùng `package.json`, lockfile, cấu hình Vite, tài liệu DEVELOPMENT/CLAUDE hoặc workflow CI của Metis làm cấu hình hay quy ước mặc định của dự án.
- Dùng template để xem bố cục, màu sắc, cách trình bày component và hành vi giao diện. Component, SCSS, asset và logic của ứng dụng được tổ chức độc lập trong source chính thức.
- Chọn dependency trực tiếp cho ứng dụng; không sao chép toàn bộ dependency hoặc số phiên bản từ template. Bootstrap được cài như dependency của ứng dụng.
- Khi thiếu hoặc xóa toàn bộ `template/`, dự án vẫn phải cài dependency, build, kiểm thử và deploy được bình thường.
- Script đóng gói/deploy phải chỉ rõ đầu vào và không đưa `template/` vào bundle hoặc upload cả repository như tài nguyên web.

Thư mục đang có trong workspace là `metis-v1.0.0/`. Lần ghi nhận tài liệu này **không di chuyển/đổi tên thư mục và không tạo hoặc sửa `.gitignore`**; quy định trên áp dụng cho dự án sẽ khởi tạo.

## 3. Tổ chức frontend

- Xây SPA Vue với component, route và logic của MLedu; chuyển cách thể hiện tham khảo từ template thành các component độc lập.
- Vue quản lý trạng thái và vòng đời component. Không đưa Alpine của template vào làm lớp quản lý trạng thái thứ hai cho cùng vùng DOM.
- Tách giao diện nội bộ và trang phụ huynh theo route/layout; quyền dữ liệu luôn được kiểm tra phía backend.
- Lựa chọn ngôn ngữ Việt/Anh và giao diện sáng/tối/theo hệ thống lưu theo trình duyệt. Lưu riêng lựa chọn `system` với màu thực tế đang áp dụng.
- In A4/A5 bằng HTML, CSS dành cho in và chức năng in trình duyệt theo REPORT-01.
- Build SPA ra thư mục output riêng, dự kiến `dist/`; cấu hình fallback để tải trực tiếp/reload route con hoạt động. Không mang cơ chế build nhiều trang của Metis sang ứng dụng.

Cloudflare có hướng dẫn [deploy Vue lên Pages](https://developers.cloudflare.com/pages/framework-guides/deploy-a-vue-site/). Pages mặc định xử lý fallback SPA khi không có `404.html` cấp gốc; khi triển khai cần kiểm tra điều kiện này trên artifact thực tế. [Nguồn routing](https://developers.cloudflare.com/pages/configuration/serving-pages/)

Các thư viện bổ trợ đã khảo sát gồm FullCalendar Standard cho lịch, Tabulator cho bảng phức tạp, Tom Select cho tìm/chọn và SweetAlert2 cho xác nhận. Đây là danh sách ứng viên; phiên bản, wrapper Vue và mức sử dụng sẽ được chốt qua kiểm tra tích hợp. SheetJS CE là ứng viên xử lý XLSX. Biểu đồ chưa chốt giữa Chart.js và ApexCharts; nếu dùng ApexCharts phải đối chiếu [điều kiện cấp phép](https://apexcharts.com/license/), không suy từ giấy phép của template.

## 4. Ranh giới backend và dữ liệu

### 4.1. API và transaction

- Workers kiểm tra request và điều phối; PostgreSQL là nơi kiểm tra lại quyền/điều kiện nghiệp vụ và ghi các thay đổi cần nguyên khối.
- Một lệnh nghiệp vụ nhiều bước gọi một RPC bao trùm toàn bộ thay đổi, audit và yêu cầu thông báo bắt buộc. Không coi nhiều request insert/update riêng lẻ là một transaction.
- Thu hẹp schema và quyền được công khai qua Data API. Chỉ cấp quyền ghi theo các lệnh đã thiết kế; kiểm tra cả truy cập trực tiếp ngoài giao diện.
- Function dùng `SECURITY DEFINER` chỉ khi cần, đặt trong phạm vi phù hợp, giới hạn quyền execute, cố định `search_path` và kiểm tra rõ người thực hiện/phạm vi. Không mặc định rằng RLS sẽ bảo vệ mọi function chạy với quyền chủ sở hữu.
- Kiểm soát phiên bản cho cập nhật, khóa các bản ghi cần thiết và dùng constraint/khóa duy nhất để chống thu trùng, tạo nghĩa vụ trùng, nhập lại file và lịch phòng chồng nhau.

### 4.2. Xác thực và phân quyền

- Phân biệt loại tài khoản Admin/Receptionist/User với vai trò giáo viên/trợ giảng theo từng lớp.
- RLS và RPC đọc trạng thái tài khoản, yêu cầu đổi mật khẩu và phân công có hiệu lực tại thời điểm yêu cầu. Không lấy workspace đang hiển thị làm quyền backend.
- Không chỉ dựa vào role trong JWT để áp dụng quyền mới tức thời; JWT có thể chưa phản ánh thay đổi đến khi refresh. [Nguồn RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- Bổ sung kiểm tra phiên hiện hành qua helper backend/database được giới hạn quyền để vô hiệu phiên đúng AUTH-02/03/04/08. Supabase hướng dẫn đối chiếu `session_id` với `auth.sessions` khi cần chặn access token còn hạn sau đăng xuất. [Nguồn sessions](https://supabase.com/docs/guides/auth/sessions)
- SPA dùng publishable key. Secret key chỉ nằm trong backend secrets; thao tác dùng quyền cao phải có kiểm tra quyền rõ ràng vì secret key bỏ qua RLS. Yêu cầu nội bộ thông thường chuyển tiếp JWT người dùng để giữ ngữ cảnh phân quyền. [Nguồn API keys](https://supabase.com/docs/guides/getting-started/api-keys)
- Quản trị tài khoản Admin dùng công cụ vận hành có audit theo AUTH-06, không thêm route quản trị Admin vào ứng dụng.

### 4.3. Trang phụ huynh

- API riêng trên Workers nhận token liên kết lớp và số điện thoại, giới hạn tần suất, chuẩn hóa rồi trả dữ liệu đúng phạm vi PORTAL-01/02/03.
- Không tạo tài khoản phụ huynh hoặc bật anonymous sign-in của Supabase cho luồng tra cứu này; phụ huynh vẫn chưa xác thực theo đặc tả.
- Không mở quyền đọc rộng các bảng học sinh, học vụ hoặc tài chính cho `anon`; endpoint public dùng truy vấn/function giới hạn dữ liệu, không để người gọi bỏ qua bước kiểm soát của API.
- Kiểm tra bật/tắt/reroll liên kết, vòng đời lớp/hồ sơ, khoảng tham gia và trạng thái công bố mỗi lần tra cứu. Dữ liệu trả về không chứa ghi chú nội bộ, phiên bản bị thay thế hoặc học vụ chưa công bố.
- Không cache chung phản hồi cá nhân hoặc phản hồi nội bộ ở CDN; asset SPA được cache độc lập với dữ liệu nghiệp vụ.

### 4.4. Lịch sử và kiểu dữ liệu

- Tách học sinh tổng, hồ sơ học sinh–lớp và lần tham gia. Nghĩa vụ tài chính gắn hồ sơ lớp; điểm gắn học sinh/bài; điểm danh gắn học sinh/buổi theo plans.md.
- Lưu riêng lịch sử phiên bản và sự kiện nghiệp vụ không thời hạn. Audit và thông báo có thời hạn 60 ngày; không dùng log nền tảng làm audit nghiệp vụ.
- Thời gian nghiệp vụ dùng `Asia/Ho_Chi_Minh`; tách ngày nghiệp vụ với timestamp sự kiện. Quyền và hạn token được kiểm tra tại request, không đợi cron.
- Tiền VND lưu bằng số nguyên; điểm dùng số chính xác đến 0,01, tránh sai số floating point. Chuẩn hóa tên/số điện thoại theo STU-04 tại backend và dùng thống nhất cho UI/API/Excel/phụ huynh.
- Lịch phòng kiểm tra theo buổi thực tế và khoảng [bắt đầu, kết thúc); có ràng buộc chống trùng khi gửi đồng thời. Trùng giờ nhân sự chỉ cảnh báo như đặc tả.

### 4.5. Avatar và luồng lưu file

- Ảnh avatar nằm trong bucket private **`avatars`**. Hồ sơ tài khoản lưu **`account_profiles.avatar_path text NULL`**, là đường dẫn tương đối trong bucket, ví dụ `<user_id>/<file_id>.webp`. Tên bucket dùng cấu hình ứng dụng; file giữ định dạng được kiểm tra, không tự đổi đuôi để giả chuyển định dạng.
- Không lưu binary, Base64 hoặc signed URL vào cột hồ sơ; không tạo FK avatar tới schema `storage`. Supabase quản lý object và metadata nội bộ; upload/di chuyển/xóa file qua Storage API. [Nguồn Storage schema](https://supabase.com/docs/guides/storage/schema/design).
- Chỉ chủ tài khoản được đổi avatar theo AUTH-08. Workers xác định user từ phiên, cấp đường dẫn mới duy nhất dưới thư mục của user, kiểm tra JPG/PNG/WebP và kích thước **tối đa 5.000.000 byte** ở backend. Không chỉ tin tên file, MIME do trình duyệt khai báo hoặc thông báo upload thành công từ client.
- Luồng đổi ảnh: xin quyền upload → tải ảnh mới lên Storage → backend xác minh file thực tế → một RPC cập nhật `avatar_path`, phiên bản hồ sơ và audit → sau khi commit mới xếp việc dọn ảnh cũ. Trước commit, avatar hiện hành vẫn là ảnh cũ.
- Storage upload và transaction PostgreSQL là hai thao tác riêng. Nếu upload thành công nhưng cập nhật hồ sơ/audit thất bại, giữ path cũ và dọn file mới chưa được tham chiếu. Việc dọn phải kiểm tra lại không có hồ sơ đang dùng file; không xóa ảnh còn hiệu lực khi có hai lần đổi ảnh đồng thời. Nhật ký/audit chỉ ghi path và thay đổi nghiệp vụ phù hợp, không ghi token/URL upload hoặc URL đọc có chữ ký.
- Khi xem ảnh, API kiểm tra quyền và cấp URL ngắn hạn hoặc tải qua luồng có xác thực. URL được sinh khi cần, không lưu làm định danh lâu dài. Signed URL còn dùng được đến hết hạn; nếu chức năng đòi thu hồi quyền đọc ngay tại từng request thì dùng luồng tải kiểm tra quyền mỗi lần. [Nguồn truy cập bucket private](https://supabase.com/docs/guides/storage/buckets/fundamentals).

Lựa chọn này chỉ áp dụng tham chiếu avatar. File Excel tạm và metadata lô nhập tiếp tục theo mô hình staging/preview ở mục 5.1 và ERD.

## 5. Excel, tác vụ và thông báo

### 5.1. Đồng bộ Excel

Luồng đã chốt: **upload private → backend đọc/kiểm tra → staging và preview → người dùng xác nhận → kiểm tra lại → một transaction áp dụng**.

- Backend kiểm tra giới hạn file dưới 10.000.000 byte, tối đa 5.000 dòng, đúng mẫu/phạm vi, `_Meta`, mã ẩn và phiên bản. Không tin dữ liệu đã được frontend kiểm tra.
- Không thực thi công thức; kiểm tra ô công thức, kiểu dữ liệu, ngày, số điện thoại dạng text và quy tắc ô trống/`XÓA`.
- Lưu dấu nội dung file thành công theo phạm vi không thời hạn; đổi tên file không vượt chống nhập lại. Preview/hủy/lỗi/không có thay đổi không đánh dấu thành công.
- Có thể chia bước đọc, chuẩn bị và lưu staging; xác nhận áp dụng vẫn nguyên khối toàn bộ file, cùng đúng một audit.
- Đo tải với 5.000 dòng và bài 50 thành phần, gồm CPU, bộ nhớ và thời gian RPC. Nếu phải dùng tiến trình parse riêng, đó là điều chỉnh nơi xử lý file; không nới giới hạn hoặc thay đổi tính nguyên khối.

Workers có giới hạn bộ nhớ 128 MB mỗi isolate; Supabase Edge Functions hiện giới hạn CPU 2 giây/request. Chưa có benchmark chứng minh parser cụ thể đáp ứng file cực đại. [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [Edge Functions limits](https://supabase.com/docs/guides/functions/limits)

### 5.2. Tác vụ nền và Realtime

- Supabase Cron quét mốc đến hạn ít nhất mỗi 5 phút; dùng lịch sử để chạy bù khi gián đoạn. [Nguồn Cron](https://supabase.com/docs/guides/cron)
- Bảng job/outbox lưu định danh sự kiện, đối tượng, trạng thái, lần thử, lỗi cuối và lần thử kế tiếp. Thử lại theo AUD-01; lỗi dữ liệu chờ dữ liệu liên quan thay đổi.
- Tạo yêu cầu thông báo cùng transaction nghiệp vụ; phân phối sau và chống trùng theo sự kiện/người nhận. Không coi tác vụ trong bộ nhớ của một request là hàng đợi bền vững.
- Realtime chỉ phát tín hiệu thay đổi tối thiểu, không phát nội dung tài chính/học vụ nhạy cảm vào kênh chung. SPA lấy dữ liệu mới qua API có kiểm tra quyền; có cơ chế đồng bộ lại khi kết nối lại.
- Quyền Broadcast channel có thể được cache trong thời gian kết nối, nên kiểm tra quyền tại lần lấy dữ liệu vẫn là bắt buộc. [Nguồn Realtime](https://supabase.com/docs/guides/realtime/authorization)

## 6. Các điểm phải kiểm chứng khi triển khai

Các mục dưới đây là tiêu chí kỹ thuật còn phải chứng minh, không phải thay đổi nghiệp vụ hoặc phương án stack đang chờ chọn:

1. Luồng Supabase Auth đáp ứng đúng link 5 phút, một lần dùng, cấp lại vô hiệu link cũ, bắt đổi mật khẩu tạm và thu hồi đúng các phiên. Cấu hình mặc định không được coi là đã đạt nghiệm thu.
2. Thiết kế audit cho thao tác Auth: gọi Auth Admin API rồi ghi audit là hai giao dịch. Phải giải quyết ranh giới này và thử lỗi để đáp ứng yêu cầu audit bắt buộc; không tự hạ xuống cơ chế bù như một ngoại lệ nghiệp vụ. Nếu nền tảng không bảo đảm được cần báo rõ để điều chỉnh triển khai hoặc thống nhất lại yêu cầu.
3. Kiểm tra quyền với token/phiên cũ, hết phân công giữa preview và xác nhận, tài khoản khóa/xóa và yêu cầu đổi mật khẩu chưa hoàn tất.
4. Kiểm tra hai yêu cầu đặt phòng/thu tiền/nhập cùng file đồng thời, lỗi audit và rollback đầy đủ.
5. Benchmark Excel cực đại, thời gian DB function và các timeout trên đường Workers → Supabase. [Nguồn timeout](https://supabase.com/docs/guides/database/postgres/timeouts)
6. Kiểm tra bản build không có template, không chứa secret; route con SPA, màn hình nhỏ và in A4/A5 hoạt động đúng.
7. Tách môi trường local/staging/production và kiểm tra khôi phục dữ liệu. Backup database của Supabase không bao gồm nội dung file trong Storage, nên cần kế hoạch sao lưu file riêng. [Nguồn backup](https://supabase.com/docs/guides/platform/backups)

Phiên bản patch, parser XLSX cuối cùng, thư viện biểu đồ, nhà cung cấp SMTP và gói compute mua thực tế chưa được chốt bởi tài liệu này. Cấu trúc source có phương án đề xuất trong [kế hoạch triển khai](../superpowers/plans/2026-10-26-trien-khai-mledu.md), cần kiểm chứng khi khởi tạo dự án.

## 7. So sánh chi phí ở quy mô MLedu

### 7.1. Phạm vi và giả định dự toán

- Quy mô đặc tả: 1.500 học sinh, 100 lớp, 100 tài khoản nội bộ; không suy thành 100 người dùng đồng thời hoặc 1.500 tài khoản Auth.
- Giá niêm yết USD được kiểm tra ngày 26/10/2026; compute theo giờ nên tổng thực tế có thể lệch mốc tháng làm tròn.
- Quy đổi minh họa **1 USD = 26.000 VND**, chỉ là tỷ giá lập ngân sách, không phải tỷ giá ngân hàng cập nhật.
- Bảng nền tảng giả định một production project, chưa vượt quota, email nằm trong gói miễn phí và không mua add-on riêng. Staging tính ở bảng riêng.
- Không gồm thuế, chênh lệch tỷ giá/phí thẻ, tên miền, nhân công phát triển/vận hành, bản quyền tùy chọn, sao lưu ngoài nền tảng, dung lượng vượt quota hoặc dịch vụ parse file bổ sung.

Kịch bản lưu lượng để tính thử, chưa phải số đo thực tế:

| Nguồn | Giả định | API request/tháng |
| --- | --- | ---: |
| Nội bộ | 100 tài khoản × 200 request/ngày × 26 ngày | 520.000 |
| Phụ huynh | Giả sử 1.500 người × 20 lượt/tháng × 5 request/lượt | 150.000 |
| Tác vụ và phần dự phòng khác | Quy ước dự toán | 50.000 |
| Tổng cơ sở | Cộng ba nhóm | **720.000** |

Nếu 720.000 request cơ sở trung bình 10 ms CPU và thêm 500 lượt xử lý file, mỗi lượt giả sử 1.000 ms CPU, tổng là **720.500 request và 7.700.000 CPU-ms/tháng**. Đây chỉ là ví dụ billing; thời gian chờ network không phải CPU, và parser phải được đo riêng. Lượng request không bao gồm các lượt tải asset tĩnh qua Pages.

### 7.2. Chi phí từng dịch vụ

| Dịch vụ | Mốc giá/dự toán | Ghi chú |
| --- | ---: | --- |
| Cloudflare Pages Free | **$0/tháng** | Hosting SPA; tối đa 500 build/tháng trên Free. API Worker được tính riêng. |
| Cloudflare Workers Paid | **từ $5/tháng** | Đã gồm 10 triệu request và 30 triệu CPU-ms/tháng; kịch bản tính thử trên nằm trong phần bao gồm. |
| Supabase Pro | **$25/tháng** | Phí tổ chức; compute được tính rồi trừ compute credit theo công thức bên dưới. |
| Supabase Micro | **khoảng $10/tháng trước credit** | Paid plan có $10 compute credit mỗi tổ chức/tháng. |
| Supabase Small | **khoảng $15/tháng trước credit** | Nâng một production project từ Micro lên Small làm tăng khoảng $5/tháng. |
| Email qua Resend Free, ví dụ để tính | **$0 trong quota** | 3.000 email/tháng, tối đa 100/ngày; cần xác minh domain và cấu hình SMTP. Nhà cung cấp chưa được chốt. |

Nguồn: [Pages limits](https://developers.cloudflare.com/pages/platform/limits/), [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [Supabase pricing](https://supabase.com/pricing), [compute và credit](https://supabase.com/docs/guides/platform/manage-your-usage/compute), [Resend quota](https://resend.com/docs/knowledge-base/account-quotas-and-limits).

Compute credit áp dụng **một lần cho mỗi tổ chức mỗi tháng**, không phải $10 cho mỗi project. Với một project Micro: Supabase ≈ $25 + $10 − $10 = **$25**. Với một project Small: ≈ $25 + $15 − $10 = **$30**. Nguồn và cách tính theo [Supabase Compute](https://supabase.com/docs/guides/platform/manage-your-usage/compute).

Để theo dõi dung lượng, Pro hiện gồm 8 GB disk/project, 100 GB file storage và 250 GB egress thông thường ở phạm vi tổ chức; quota Auth là 100.000 MAU. Với 100 tài khoản nội bộ, chi phí Auth theo MAU chưa phải yếu tố chính. Dữ liệu lịch sử giữ lâu dài vẫn cần theo dõi tăng trưởng; không khẳng định dung lượng đủ vĩnh viễn. [Nguồn quota/billing](https://supabase.com/docs/guides/platform/billing-on-supabase)

Realtime Pro gồm 5 triệu message/tháng; phần vượt được tính theo gói triệu message. Ước lượng phải tính số lần phân phối tới các subscriber, không chỉ số bản ghi thông báo. [Nguồn Realtime usage](https://supabase.com/docs/guides/platform/manage-your-usage/realtime-messages)

### 7.3. So sánh các phương án production

| Phương án | Công thức tháng | USD/tháng | VND/tháng minh họa | USD/năm |
| --- | --- | ---: | ---: | ---: |
| **Đã chọn: Pages + Workers Paid + Supabase Pro/Micro** | 0 + 5 + (25 + 10 − 10) | **≈ $30** | **780.000** | **≈ $360** |
| **Đã chọn, nâng DB Small** | 0 + 5 + (25 + 15 − 10) | **≈ $35** | **910.000** | **≈ $420** |
| Phương án so sánh: Pages + Supabase Edge Functions/Micro | 0 + (25 + 10 − 10), function trong quota | ≈ $25 | 650.000 | ≈ $300 |
| Phương án so sánh: Laravel + PostgreSQL tự quản trên một VPS | VPS $24 + backup hằng ngày 30% | ≈ $31.20 | 811.200 | ≈ $374.40 |

Phương án Supabase Edge Functions giả định không dùng Workers Paid, không có tiến trình parse bổ sung và không vượt 2 triệu lượt gọi function/tháng của Pro. Tiết kiệm khoảng $5/tháng so với stack đã chọn, nhưng phải kiểm chứng runtime Excel trước. [Nguồn function usage](https://supabase.com/docs/guides/platform/manage-your-usage/edge-function-invocations)

VPS minh họa là DigitalOcean Basic Regular 4 GiB RAM/2 vCPU giá $24/tháng; backup hằng ngày cộng 30%, tức $7.20. Phương án này tự vận hành ứng dụng, PostgreSQL, worker, cập nhật hệ điều hành và phục hồi. Bảng không mặc định VPS đáp ứng tải và không coi tài nguyên/SLA của VPS tương đương Supabase managed. [Giá Droplet](https://www.digitalocean.com/pricing/droplets), [giá backup](https://www.digitalocean.com/pricing/backups)

So với VPS $31.20, stack đã chọn Micro thấp hơn khoảng $1.20/tháng, Small cao hơn khoảng $3.80/tháng. Chênh lệch tiền nền tảng nhỏ; lợi ích của lựa chọn đã chốt nằm ở dịch vụ Auth/Storage/Realtime được quản lý và giảm việc quản trị máy chủ. Đổi lại, cần đầu tư thiết kế RPC/RLS và kiểm thử các giới hạn runtime. Chưa có dữ liệu để định giá nhân công hay kết luận tổng chi phí sở hữu bằng một con số.

### 7.4. Khi thêm staging

| Môi trường trong cùng một tổ chức Pro | Supabase/tháng | Cộng Workers Paid | Tổng nền tảng/tháng |
| --- | ---: | ---: | ---: |
| Production Micro + staging Micro | 25 + 10 + 10 − 10 = $35 | $5 | **≈ $40** |
| Production Small + staging Micro | 25 + 15 + 10 − 10 = $40 | $5 | **≈ $45** |

Giả định Workers production/staging cùng tài khoản Paid và tổng usage còn trong quota; không cộng thêm $5 chỉ vì có thêm một Worker. Supabase tính compute riêng từng project; không có project Free trong cùng một tổ chức Pro. Có thể dùng local cho phát triển hoặc tổ chức Free riêng cho môi trường thử nghiệm phù hợp giới hạn. [Nguồn Supabase organization billing](https://supabase.com/docs/guides/platform/billing-on-supabase), [nguồn Workers account pricing](https://developers.cloudflare.com/workers/platform/pricing/)

### 7.5. Ngân sách đề xuất và các khoản làm tăng hóa đơn

- Dùng **$30/tháng** làm mốc nền tảng cho một production Micro; dự trù **$35–50/tháng**, tương đương **910.000–1.300.000 VND/tháng** theo tỷ giá quy ước, để có khoảng nâng compute hoặc biến động nhỏ. Khoảng dự trù không phải gói dịch vụ hoặc trần hóa đơn.
- Nếu giữ staging trả phí liên tục, dùng mốc **$40–45/tháng** trước phần dự phòng và các khoản loại trừ. Việc chọn Micro hay Small phải dựa vào đo tải và theo dõi CPU, RAM, query/lock, không chỉ số lượng học sinh.
- Audit 60 ngày của MLedu nằm trong database ứng dụng và có tính vào dung lượng; retention log của nhà cung cấp không thay cho audit này.
- Supabase Pro có backup database hằng ngày, giữ 7 ngày. Nếu cần phục hồi tới thời điểm gần sự cố hơn, PITR là add-on riêng: mốc 7 ngày khoảng $100/tháng và cần tối thiểu compute Small. Như vậy stack Small + Workers + PITR vào khoảng **$135/tháng**, chưa gồm staging/chi phí khác. Đây là lựa chọn về phục hồi chưa được quyết định mua. [Nguồn backup/PITR](https://supabase.com/docs/guides/platform/backups)
- Sao lưu nội dung Storage ra nơi khác, tên miền, email trả phí, dung lượng/egress vượt quota, tăng compute và tiến trình parse riêng có thể phát sinh thêm. Chưa gộp các khoản chưa có yêu cầu hoặc số đo vào mốc $30/$35.
- Giới hạn CPU mỗi request, giới hạn tần suất tra cứu công khai và cảnh báo usage giúp kiểm soát chi phí. Kiểm tra lại bảng giá khi triển khai; không coi spend cap là trần cho mọi hạng mục, đặc biệt compute. [Nguồn compute billing](https://supabase.com/docs/guides/platform/manage-your-usage/compute)
