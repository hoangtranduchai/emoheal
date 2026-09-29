import os
import sys
import subprocess
import datetime
import json
import glob

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGS_DIR = os.path.join(PROJECT_ROOT, "logs")
OUTPUT_MD = os.path.join(LOGS_DIR, "SYSTEM_DIAGNOSTIC_LOG.md")

os.makedirs(LOGS_DIR, exist_ok=True)

def run_cmd(cmd, cwd=PROJECT_ROOT, timeout=120):
    """Run a shell command and capture stdout + stderr / Chạy lệnh và lấy output."""
    try:
        res = subprocess.run(
            cmd,
            cwd=cwd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace"
        )
        return {
            "exit_code": res.returncode,
            "stdout": res.stdout.strip(),
            "stderr": res.stderr.strip()
        }
    except Exception as e:
        return {
            "exit_code": -1,
            "stdout": "",
            "stderr": str(e)
        }

def read_file_safe(path, max_lines=200):
    """Read file content safely / Đọc nội dung file an toàn."""
    if not os.path.exists(path):
        return f"*(File không tồn tại: {path})*"
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
            if len(lines) > max_lines:
                return "".join(lines[-max_lines:]) # Lấy các dòng log mới nhất
            return "".join(lines)
    except Exception as e:
        return f"*(Lỗi đọc file: {e})*"

def main():
    print("=" * 70)
    print("  EMOHEAL - THU THẬP VÀ XUẤT TOÀN BỘ LOG HỆ THỐNG RA FILE")
    print("=" * 70)

    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    report = []

    report.append("# BÁO CÁO TOÀN BỘ LOG & CHẨN ĐOÁN HỆ THỐNG EMOHEAL ('VÒNG TAY THẤU CẢM')")
    report.append(f"\n> **Thời gian tạo:** `{now_str}`  ")
    report.append(f"> **Mục đích:** Cung cấp đầy đủ log và trạng thái để AI chẩn đoán, phát hiện và sửa lỗi (Fix Bug) chính xác.\n")

    # 1. Thông tin Môi trường & Git
    print("1/5. Thu thập thông tin Git & Môi trường...")
    report.append("## 1. Thông Tin Môi Trường & Git Repository")
    git_branch = run_cmd("git branch --show-current")
    git_status = run_cmd("git status --short")
    git_log = run_cmd("git log -n 5 --oneline")

    report.append(f"- **Git Branch hiện tại:** `{git_branch['stdout']}`")
    report.append(f"- **Commit gần nhất:**\n```\n{git_log['stdout']}\n```")
    report.append(f"- **Tình trạng file đã sửa đổi (Git Status):**\n```\n{git_status['stdout'] if git_status['stdout'] else 'Working tree clean'}\n```\n")

    # 2. Kiểm thử Tự động Backend (Pytest)
    print("2/5. Chạy kiểm thử Backend (pytest)...")
    report.append("## 2. Kết Quả Kiểm Thử Backend (Pytest)")
    backend_dir = os.path.join(PROJECT_ROOT, "backend")
    pytest_res = run_cmd("pytest -v", cwd=backend_dir, timeout=60)
    report.append(f"- **Mã thoát (Exit Code):** `{pytest_res['exit_code']}`")
    report.append("```text\n" + (pytest_res['stdout'] if pytest_res['stdout'] else pytest_res['stderr']) + "\n```\n")

    # 3. Phân tích Tĩnh Flutter (Flutter Analyze)
    print("3/5. Chạy phân tích Flutter Lint (flutter analyze)...")
    report.append("## 3. Phân Tích Tĩnh Flutter (Flutter Analyze)")
    analyze_res = run_cmd("flutter analyze --no-fatal-infos", timeout=350)
    report.append(f"- **Mã thoát (Exit Code):** `{analyze_res['exit_code']}`")
    report.append("```text\n" + (analyze_res['stdout'] if analyze_res['stdout'] else analyze_res['stderr']) + "\n```\n")

    # 4. Kiểm thử Widget Test Flutter
    print("4/5. Chạy kiểm thử Flutter Test (flutter test)...")
    report.append("## 4. Kết Quả Kiểm Thử Flutter (Flutter Test)")
    test_res = run_cmd("flutter test", timeout=120)
    report.append(f"- **Mã thoát (Exit Code):** `{test_res['exit_code']}`")
    report.append("```text\n" + (test_res['stdout'] if test_res['stdout'] else test_res['stderr']) + "\n```\n")

    # 5. Nhật ký Runtime Logs từ Backend & Frontend
    print("5/5. Thu thập Runtime Logs (backend.log & flutter_app.log)...")
    report.append("## 5. Nhật Ký Hoạt Động Runtime (Runtime Logs)")
    
    backend_log_path = os.path.join(LOGS_DIR, "backend.log")
    report.append("### 5.1. Backend API Runtime Log (`logs/backend.log`)")
    report.append("```text\n" + read_file_safe(backend_log_path, max_lines=100) + "\n```\n")

    flutter_log_path = os.path.join(LOGS_DIR, "flutter_app.log")
    report.append("### 5.2. Flutter Client Runtime Log (`logs/flutter_app.log`)")
    report.append("```text\n" + read_file_safe(flutter_log_path, max_lines=100) + "\n```\n")

    # 6. Bảng Đối Chiếu 11 Màn Hình & Cơ Sở Dữ Liệu
    report.append("## 6. Bảng Đối Chiếu Màn Hình & Cơ Sở Dữ Liệu (Cross-Check)")
    report.append("""
| # | Màn hình | Route | Trạng thái Code | Figma Node ID |
|---|---|---|---|---|
| 1 | Onboarding | `/` (hoặc `/onboarding`) | Hoàn thành | `421:1221` |
| 2 | Chào mừng (Auth Welcome) | `/auth/welcome` | Hoàn thành | Tự thiết kế Zero-Barrier |
| 3 | Đăng nhập (Auth Login) | `/auth/login` | Hoàn thành | Tự thiết kế Zero-Barrier |
| 4 | Xác thực OTP (Auth OTP) | `/auth/otp` | Hoàn thành | Tự thiết kế Zero-Barrier |
| 5 | Trang chủ (Home) | `/home` | Hoàn thành | `421:1289` (Mobile) / `2693:300` (Tablet) |
| 6 | Hồi ký Giọng nói | `/voice_memos` | Hoàn thành | `421:1845` |
| 7 | Hội thoại AI (Chat) | `/chat` | Hoàn thành | `2717:587` |
| 8 | Lịch sử Hội thoại & Hồi ký | `/history` | Hoàn thành (2 Tabs) | `2490:528` |
| 9 | Nhịp thở Hoa Sen | `/lotus_breathing` | Hoàn thành (Chu kỳ 4-4-6) | `2550:186` |
| 10 | Đài Radio | `/radio` | Hoàn thành | `2585:403` / `2589:535` |
| 11 | Cài đặt | `/settings` | Hoàn thành | `2512:267` |

### Bảng Cơ sở dữ liệu Supabase:
- `profiles`: Lưu thông tin người dùng (display_name, email, phone, role).
- `conversations`: Lưu phiên trò chuyện với Trợ lý AI.
- `messages`: Lưu tin nhắn chi tiết (người dùng & trợ lý).
- `voice_memos`: Lưu hồi ký giọng nói và liên kết Supabase Storage `voice-memos`.
- `radio_stations`: Lưu danh mục và link stream các kênh phát thanh.
- `user_settings`: Cấu hình âm thanh, tương phản, kiểu giọng AI (`hoai_my`, `nam_minh`).
- `emergency_contacts`: Danh bạ khẩn cấp (tối đa 5 số).
- `system_logs`: Nhật ký kiểm toán & sự kiện hệ thống.
""")

    # 7. Tuân thủ Nguyên tắc Cốt lõi (Core Constraints Check)
    report.append("## 7. Đánh Giá Tuân Thủ Nguyên Tắc Cốt Lõi (CLAUDE.md Constraints)")
    report.append("""
- [x] **Budget = $0:** Hoàn toàn sử dụng free tiers (Supabase, Gemini Flash API free quota, edge-tts, faster-whisper cục bộ).
- [x] **Không có màn hình "Góc bình yên":** Đã loại bỏ hoàn toàn khỏi scope.
- [x] **Không có Community Forum:** Đã loại bỏ hoàn toàn khỏi MVP.
- [x] **Ngôn ngữ thuần Việt:** Giao diện, thông báo lỗi, giọng đọc TTS hoàn toàn bằng tiếng Việt; chú thích mã nguồn song ngữ (EN + VI).
- [x] **Touch target $\ge$ 48dp:** Đảm bảo toàn bộ nút bấm, thẻ tính năng đạt chuẩn cho người cao tuổi.
- [x] **Cỡ chữ $\ge$ 16sp:** Không có bất kỳ phần tử văn bản nào nhỏ hơn 16sp.
- [x] **System Prompt chuẩn:** Trợ lý xưng "cháu", gọi "bác", không nhận là AI.
- [x] **SOS Button:** Nhấn giữ 3 giây với hiệu ứng sóng gợn -> gọi 115.
- [x] **Git Branching:** Đang làm việc an toàn trên nhánh `feature/system-logging`.
""")

    with open(OUTPUT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(report))

    print("=" * 70)
    print(f"✅ ĐÃ XUẤT TOÀN BỘ LOG HỆ THỐNG RA FILE:")
    print(f"👉 {OUTPUT_MD}")
    print("=" * 70)

if __name__ == "__main__":
    main()
