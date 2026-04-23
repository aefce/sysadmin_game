#!/bin/bash
# ==============================================================================
# 專案名稱: SysAdmin Hero: Ultimate Encyclopedia Edition (終極百科全書版)
# 作者: [你的名字]
# 描述: 
# 1. 包含 10 個完整關卡 (Grep, Chmod, Kill, Tar, Free, Ping, Find, Sed, Ln, Rm)
# 2. 內建教科書等級的 Help 說明手冊 (Scrollable Man Page)
# 3. 實作排行榜 (Upsert 邏輯)、視覺化介面 (TUI)、操作歷程 (History)
# 4. 智慧判定系統：支援帶參數指令白名單，不誤扣分
# ==============================================================================

# ------------------------------------------------
# 1. 系統全域設定 (Global Settings)
# ------------------------------------------------
# 攔截所有中斷訊號，防止玩家中途跳車
trap '' SIGINT SIGQUIT SIGTSTP

# ANSI 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# 遊戲狀態變數
SCORE=0
HEALTH=100
PLAYER_NAME=""
# 遊戲暫存目錄 (在 /tmp 隨機產生)
GAME_DIR="/tmp/sysadmin_game_$(date +%s)"
# 排行榜存檔 (存在使用者家目錄，確保永久保存)
SCORE_FILE="$HOME/.sysadmin_highscore.dat"
# 滿分設定
MAX_SCORE=300

# ------------------------------------------------
# 2. 視覺化模組 (Visual TUI Module)
# ------------------------------------------------
check_tools() {
    if ! command -v whiptail &> /dev/null; then
        echo "正在安裝必要套件 whiptail..."
        sudo apt-get install -y whiptail &> /dev/null
    fi
}

msg_box() {
    # $1:標題 $2:內容
    whiptail --title "$1" --msgbox "$2" 12 70
}

scroll_box() {
    # $1:標題 $2:檔案路徑 (用於顯示長篇文字)
    whiptail --title "$1" --textbox "$2" 20 75 --scrolltext
}

input_box() {
    # $1:標題 $2:描述 $3:預設值
    whiptail --title "$1" --inputbox "$2" 10 60 "$3" 3>&1 1>&2 2>&3
}

menu_box() {
    whiptail --title "SysAdmin Hero - Main Menu" --menu "歡迎來到系統管理員模擬器，請選擇功能：" 18 70 6 \
    "1" "開始救援任務 (Start Game)" \
    "2" "查看排行榜 (Leaderboard)" \
    "3" "指令百科全書 (Manual)" \
    "4" "關於本遊戲 (About)" \
    "5" "離開系統 (Exit)" 3>&1 1>&2 2>&3
}

progress_bar() {
    local text=$1
    local duration=$2
    {
        for ((i = 0 ; i <= 100 ; i+=5)); do
            sleep $(awk "BEGIN {print $duration / 20}")
            echo $i
        done
    } | whiptail --gauge "$text" 6 60 0
}

# ------------------------------------------------
# 3. 排行榜邏輯 (Leaderboard Logic)
# ------------------------------------------------
update_score() {
    # 邏輯：只保留該玩家的最高分 (Upsert)
    if [ ! -f "$SCORE_FILE" ]; then
        echo "$SCORE $PLAYER_NAME $(date +%Y-%m-%d)" > "$SCORE_FILE"
        return
    fi

    # 找舊分數
    local old_score=$(awk -v user="$PLAYER_NAME" '$2 == user {print $1}' "$SCORE_FILE" | sort -nr | head -n 1)

    if [ -z "$old_score" ]; then
        # 新玩家
        echo "$SCORE $PLAYER_NAME $(date +%Y-%m-%d)" >> "$SCORE_FILE"
    elif [ "$SCORE" -gt "$old_score" ]; then
        # 打破紀錄：先刪除舊的，再加新的
        local temp_file="${SCORE_FILE}.tmp"
        awk -v user="$PLAYER_NAME" '$2 != user' "$SCORE_FILE" > "$temp_file"
        echo "$SCORE $PLAYER_NAME $(date +%Y-%m-%d)" >> "$temp_file"
        mv "$temp_file" "$SCORE_FILE"
        whiptail --title "NEW RECORD" --msgbox "太神啦！\n恭喜打破個人紀錄！\n舊分數: $old_score -> 新分數: $SCORE" 10 60
    fi
}

show_leaderboard() {
    if [ ! -f "$SCORE_FILE" ]; then
        msg_box "排行榜" "目前還沒有紀錄。\n\n檔案位置: $SCORE_FILE"
        return
    fi
    # 格式化輸出
    local board=$(sort -nr -k1 "$SCORE_FILE" | head -n 10 | awk '{printf "No.%-2d : %-4s 分 - %-10s (%s)\n", NR, $1, $2, $3}')
    msg_box "英雄榜 (Top 10)" "$board"
}

# ------------------------------------------------
# 4. 遊戲核心與 HUD (Game Engine)
# ------------------------------------------------
trigger_game_over() {
    whiptail --title "GAME OVER" --msgbox "核心崩潰 (Kernel Panic)！\n救援任務失敗。\n\n最終得分: $SCORE" 10 60
    rm -rf "$GAME_DIR"
    exit_flag=1 # 設定旗標，中止後續任務
    return
}

take_damage() {
    local dmg=$1
    local reason=$2
    HEALTH=$((HEALTH - dmg))
    echo -e "${RED}[警告] $reason (系統完整度 -$dmg)${RESET}"
    if [ $HEALTH -le 0 ]; then 
        sleep 1
        trigger_game_over
    fi
}

show_dashboard() {
    clear
    # 讀取真實系統資訊
    local kernel=$(uname -r)
    local ip=$(hostname -I 2>/dev/null | cut -d' ' -f1)
    [ -z "$ip" ] && ip="127.0.0.1"
    
    echo -e "${BLUE}================================================================${RESET}"
    echo -e "${BLUE}       SYSADMIN HERO: ULTIMATE ENCYCLOPEDIA EDITION             ${RESET}"
    echo -e "${BLUE}================================================================${RESET}"
    echo -e "${CYAN}Kernel: $kernel | IP: $ip${RESET}"
}

print_hud() {
    local goal=$1
    echo -e "${BLUE}----------------------------------------------------------------${RESET}"
    echo -e "${YELLOW}🎯 當前目標：${RESET} $goal"
    echo -e "${RED}❤️  生命值：$HEALTH%${RESET}  |  ${GREEN}🏆 分數：$SCORE${RESET}  |  ${CYAN}💡 提示：輸入 'hint'${RESET}"
    echo -e "${BLUE}----------------------------------------------------------------${RESET}"
}

# ------------------------------------------------
# 5. 超詳細說明手冊 (Encyclopedia)
# ------------------------------------------------
show_help() {
    # 建立一個暫存檔來放長篇說明
    local help_file="/tmp/sysadmin_manual.txt"
    
    cat << EOF > "$help_file"
============================================================
           SYSADMIN HERO - 指令百科全書 (Manual)
============================================================

[章節 1: 基礎檔案操作]
------------------------------------------------------------
1. ls (List)
   描述: 列出目錄中的檔案與資料夾。
   常用: ls -l (詳細列表，顯示權限、擁有者、大小)
   範例: ls -l /home

2. cd (Change Directory)
   描述: 切換目前的目錄。
   範例: cd /var/log (進入 logs 資料夾)
         cd ..       (回到上一層)

3. pwd (Print Working Directory)
   描述: 顯示目前所在的完整路徑。

4. cat (Concatenate)
   描述: 查看檔案內容。
   範例: cat filename.txt

5. mv (Move)
   描述: 移動檔案，或重新命名。
   範例: mv old.txt new.txt (改名)
         mv file.txt /tmp/  (移動)

6. cp (Copy)
   描述: 複製檔案。
   範例: cp original.txt backup.txt

7. rm (Remove)
   描述: 刪除檔案 (小心使用！)。
   範例: rm junk.txt

8. touch
   描述: 建立一個空的檔案。
   範例: touch newfile.c

[章節 2: 系統安全與權限]
------------------------------------------------------------
9. chmod (Change Mode)
   描述: 修改檔案權限。
   數值: 4(讀r) + 2(寫w) + 1(執行x)
   常用:
     - 777 (rwxrwxrwx): 所有人都可讀寫執行 (危險)
     - 600 (rw-------): 只有擁有者可讀寫 (安全)
     - 644 (rw-r--r--): 擁有者可寫，其他人唯讀
   範例: chmod 600 config.conf

10. sudo (SuperUser DO)
    描述: 以管理員 (root) 權限執行指令。
    範例: sudo apt update

[章節 3: 搜尋與過濾]
------------------------------------------------------------
11. grep (Global Regular Expression Print)
    描述: 在檔案內容中搜尋關鍵字。
    語法: grep "關鍵字" 檔案名
    範例: grep "Error" application.log

12. find
    描述: 在目錄結構中搜尋檔案。
    語法: find 路徑 -name "檔名"
    範例: find . -name "*.jpg"

[章節 4: 行程與系統資源]
------------------------------------------------------------
13. ps (Process Status)
    描述: 列出目前執行的程序。
    範例: ps aux

14. kill
    描述: 終止指定的程序 (需配合 PID)。
    範例: kill 1234

15. free
    描述: 查看記憶體使用量。
    範例: free -h (人類可讀單位)

16. df (Disk Free)
    描述: 查看磁碟空間。
    範例: df -h

17. uptime
    描述: 查看系統運行時間與負載。

[章節 5: 進階管理指令]
------------------------------------------------------------
18. tar (Tape Archiver)
    描述: 打包與壓縮檔案。
    語法: tar -czvf <產出檔名.tar.gz> <來源檔>
    參數: c(建立), z(gzip壓縮), v(顯示過程), f(指定檔名)
    範例: tar -czvf backup.tar.gz /data

19. ping
    描述: 測試網路連線。
    範例: ping 8.8.8.8

20. sed (Stream Editor)
    描述: 串流文字編輯器，常用於取代字串。
    語法: sed -i 's/舊字串/新字串/' 檔名
    範例: sed -i 's/False/True/' config.ini

21. ln (Link)
    描述: 建立連結 (捷徑)。
    語法: ln -s <目標> <捷徑名>
    範例: ln -s /var/www/html web

============================================================
                 (按 q 或 Enter 離開本手冊)
============================================================
EOF

    # 使用 scroll_box 顯示長篇內容
    scroll_box "指令百科全書" "$help_file"
    rm "$help_file"
    
    # 返回主畫面
    show_dashboard
}

# ------------------------------------------------
# 6. 初始化與劇情鋪陳
# ------------------------------------------------
init_game() {
    exit_flag=0 
    PLAYER_NAME=$(input_box "身分驗證" "請輸入您的系統代號 (Name):" "$USER")
    if [ -z "$PLAYER_NAME" ]; then PLAYER_NAME="Guest"; fi
    # 移除名字中的空白，避免錯誤
    PLAYER_NAME=$(echo "$PLAYER_NAME" | tr -d ' ')

    progress_bar "正在初始化虛擬檔案系統..." 2
    
    # 建立完整目錄結構
    mkdir -p "$GAME_DIR"/{logs,conf,backup,data,www,uploads}
    mkdir -p "$GAME_DIR/data/lost/found/deep"
    mkdir -p "$GAME_DIR/www/public_html"
    
    # 1. 產生假資料庫
    dd if=/dev/zero of="$GAME_DIR/data/database.db" bs=1M count=5 status=none
    
    # 2. 產生設定檔 (亂數密碼 + Base64)
    local token=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    echo "ROOT_TOKEN=$(echo "$token" | base64)" > "$GAME_DIR/conf/secret.conf"
    chmod 777 "$GAME_DIR/conf/secret.conf"
    
    # 3. M8 設定檔
    echo "SERVER_IP=10.0.0.1" > "$GAME_DIR/conf/webapp.conf"
    echo "DB_PORT=3306" >> "$GAME_DIR/conf/webapp.conf"
    
    # 4. M9 網頁檔
    echo "<h1>It Works!</h1>" > "$GAME_DIR/www/public_html/index.html"

    # 5. M10 駭客後門
    touch "$GAME_DIR/uploads/backdoor.sh"
    chmod +x "$GAME_DIR/uploads/backdoor.sh"

    # 6. M7 隱藏檔案
    touch "$GAME_DIR/data/lost/found/deep/legacy_code.c"
    
    # 7. 產生 Logs
    for i in {1..8}; do
        echo "[INFO] User root login from 192.168.1.$((RANDOM % 255))" >> "$GAME_DIR/logs/auth.log"
    done
    echo "[DANGER] SSH Brute force detected from 66.249.1.5" >> "$GAME_DIR/logs/auth.log"
}

intro_story() {
    msg_box "緊急通知 (Emergency Alert)" "時間：週五晚上 11:59\n地點：主要伺服器機房\n\n監控儀表板全是紅燈。駭客集團 'NullPointer' 發動了全面攻擊。\n資料庫權限被篡改、核心出現未授權行程、網頁服務設定被綁架。\n\n你，是今晚唯一的守門員。"
}

# ------------------------------------------------
# 7. 職前訓練 (10分)
# ------------------------------------------------
training_phase() {
    [ $exit_flag -eq 1 ] && return
    msg_box "職前訓練中心" "在授權 Root 權限前，必須通過指令考核。\n(共 5 題，每題 2 分，共 10 分)\n\n[提示] 遇到不會的題目，輸入 'hint' 可看提示。"
    
    ask() {
        local q=$1; local a=$2; local h=$3
        while true; do
            echo -e "${YELLOW}[Q] $q${RESET}"
            read -e -p "> " ans
            history -s "$ans"
            local clean=$(echo "$ans" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$clean" == "$a" ]]; then
                echo -e "${GREEN}Correct! (+2)${RESET}"; SCORE=$((SCORE+2)); break
            elif [[ "$clean" == "hint" ]]; then
                echo -e "${CYAN}[提示] $h${RESET}"
            elif [[ "$clean" == "help" ]]; then
                show_help
            else
                echo -e "${RED}Wrong.${RESET}"
            fi
        done
        echo "------------------------------------------------"
    }
    
    clear
    ask "顯示目前完整路徑？" "pwd" "Print Working Directory"
    ask "提升超級管理員權限？" "sudo" "SuperUser DO"
    ask "移動檔案或重新命名？" "mv" "Move"
    ask "建立一個空檔案？" "touch" "Touch"
    ask "查看指令說明書？" "man" "Manual"
    
    msg_box "考核通過" "目前分數: $SCORE\n權限已解鎖，正在連線至受駭伺服器..."
}

# ------------------------------------------------
# 8. 正式關卡通用引擎 (修正判定邏輯)
# ------------------------------------------------
run_mission() {
    [ $exit_flag -eq 1 ] && return
    local name=$1
    local goal=$2
    local hint=$3
    local dir=$4
    local score_add=$5
    local check_cmd=$6
    
    msg_box "$name" "$goal"
    show_dashboard; cd "$dir"
    
    while true; do
        print_hud "$goal"
        read -e -p "root@server:$(pwd | sed "s|$GAME_DIR|~|")# " c
        history -s "$c"
        
        # 內建指令
        if [[ "$c" == "hint" ]]; then echo -e "${CYAN}[提示] $hint${RESET}"; continue; fi
        if [[ "$c" == "help" ]]; then show_help; continue; fi
        
        # Ping 保護
        if [[ "$c" == "ping"* && "$c" != *"-c"* ]]; then
             echo -e "${YELLOW}[系統保護] 自動加入 -c 3${RESET}"
             c="$c -c 3"
        fi

        # 執行指令
        eval "$c" 2>/dev/null
        
        # 驗證成功
        if $check_cmd "$c"; then
            echo -e "${GREEN}>> 任務完成！ (+$score_add 分) <<${RESET}"
            SCORE=$((SCORE+score_add))
            sleep 1
            break
        fi
        
        # === 關鍵修正：白名單判定 (Regex Start With) ===
        # 只要指令以這些關鍵字開頭，就不扣分 (允許參數，如 cat file)
        if [[ "$c" =~ ^(ls|cd|pwd|cat|head|tail|file|du|stat|echo|hint|help|man|whoami|id|grep|chmod|ps|kill|tar|free|df|uptime|ping|find|sed|ln|rm) ]]; then
            continue
        fi
        
        # 如果是空指令也不扣分
        if [[ -z "$c" ]]; then continue; fi
        
        take_damage 10 "無效指令或拼字錯誤"
        [ $exit_flag -eq 1 ] && return
    done
}

# --- 驗證函式 ---
check_m1() { [[ "$1" == *"grep"* && "$1" == *"66.249.1.5"* ]]; }
check_m2() { [ "$(stat -c "%a" secret.conf 2>/dev/null)" == "600" ]; }
check_m3() { [[ "$1" == *"kill"* && "$1" == *"666"* ]]; } 
check_m4() { [ -f "backup.tar.gz" ]; }
check_m5() { [[ "$1" == *"uptime"* ]]; } # 簡化判定
check_m6() { [[ "$1" == *"ping"* && "$1" == *"8.8.8.8"* ]]; }
check_m7() { [[ "$1" == *"find"* && "$1" == *"legacy_code.c"* ]]; }
check_m8() { grep -q "127.0.0.1" webapp.conf; }
check_m9() { [ -L "html" ]; }
check_m10() { [ ! -f "backdoor.sh" ]; }

# ------------------------------------------------
# 9. 關卡序列
# ------------------------------------------------
run_all_missions() {
    # M1
    run_mission "任務 1/10: Log 鑑識" "找出 logs/auth.log 中 DANGER 的 IP" \
    "grep 'DANGER' logs/auth.log" "$GAME_DIR" 20 check_m1

    # M2
    run_mission "任務 2/10: 權限加固" "將 conf/secret.conf 權限改為 600" \
    "chmod 600 secret.conf\n(可先用 ls -l 查看)" \
    "$GAME_DIR/conf" 30 check_m2

    # M3 特殊處理
    [ $exit_flag -eq 1 ] && return
    msg_box "任務 3/10: 行程終止" "kill 掉惡意行程 (PID 666)"
    show_dashboard; cd "$GAME_DIR"
    while true; do
        print_hud "kill 掉惡意行程 (PID 666)"
        read -e -p "root@server:~# " c
        history -s "$c"
        if [[ "$c" == "hint" ]]; then echo -e "${CYAN}[提示] ps -> kill 666${RESET}"; continue; fi
        if [[ "$c" == "help" ]]; then show_help; continue; fi
        if [[ "$c" == *"ps"* ]]; then echo -e "PID\tCMD\n1\tsystemd\n666\t./miner"; continue; fi
        if [[ "$c" == *"kill"* && "$c" == *"666"* ]]; then echo -e "${GREEN}Done!${RESET}"; SCORE=$((SCORE+30)); break; fi
        if [[ "$c" =~ ^(ls|pwd|cd|cat)$ ]]; then continue; fi
        take_damage 10 "指令錯誤"; [ $exit_flag -eq 1 ] && return
    done

    # M4
    run_mission "任務 4/10: 災難備份" "將 data/database.db 備份為 backup.tar.gz" \
    "tar -czvf backup.tar.gz database.db" "$GAME_DIR/data" 30 check_m4

    # M5 特殊處理
    [ $exit_flag -eq 1 ] && return
    msg_box "任務 5/10: 系統報告" "依序執行: free, df, uptime"
    show_dashboard
    for cmd in "free" "df" "uptime"; do
        while true; do
            print_hud "執行系統檢查指令: $cmd"
            read -e -p "Check > " c
            history -s "$c"
            [[ "$c" == "hint" ]] && { echo -e "${CYAN}[提示] 直接輸入 $cmd${RESET}"; continue; }
            [[ "$c" == "help" ]] && { show_help; continue; }
            eval "$c" 2>/dev/null
            if [[ "$c" == *"$cmd"* ]]; then echo -e "${GREEN}OK${RESET}"; break; else take_damage 5 "指令錯誤"; fi
            [ $exit_flag -eq 1 ] && return
        done
    done
    SCORE=$((SCORE+20))

    # M6
    run_mission "任務 6/10: 網路檢測" "Ping Google DNS (8.8.8.8)" \
    "ping 8.8.8.8" "$GAME_DIR" 20 check_m6

    # M7
    run_mission "任務 7/10: 檔案搜尋" "在 data 目錄中搜尋遺失的 'legacy_code.c'" \
    "find . -name 'legacy_code.c'" "$GAME_DIR/data" 30 check_m7

    # M8
    run_mission "任務 8/10: 設定修正" "將 conf/webapp.conf 中的 10.0.0.1 修改為 127.0.0.1" \
    "sed -i 's/10.0.0.1/127.0.0.1/' webapp.conf" "$GAME_DIR/conf" 30 check_m8

    # M9
    run_mission "任務 9/10: 連結修復" "在 www 目錄，為 public_html 建立捷徑名稱 'html'" \
    "ln -s public_html html" "$GAME_DIR/www" 30 check_m9

    # M10
    run_mission "任務 10/10: 清除後門" "在 uploads 目錄刪除 'backdoor.sh'" \
    "rm backdoor.sh" "$GAME_DIR/uploads" 30 check_m10
}

# ------------------------------------------------
# 10. 主入口
# ------------------------------------------------
start_game() {
    SCORE=0
    HEALTH=100
    init_game
    intro_story
    training_phase
    run_all_missions
    
    if [ $exit_flag -eq 0 ]; then
        update_score
        whiptail --title "MISSION COMPLETE" --msgbox "恭喜 $PLAYER_NAME！\n10 項任務圓滿完成。\n\n最終得分: $SCORE / $MAX_SCORE" 12 60
        clear
        echo -e "${BLUE}=========================================${RESET}"
        echo -e "       S Y S A D M I N   H E R O         "
        echo -e "=========================================${RESET}"
        echo -e "Credits:"
        echo -e "  Lead Developer: $PLAYER_NAME"
        echo -e "  Engine: Bash Shell + Whiptail TUI"
        echo -e "  OS Simulation: Linux Kernel"
        echo ""
        echo "按 Enter 返回主選單..."
        read
    fi
    rm -rf "$GAME_DIR"
}

main_menu() {
    while true; do
        check_tools
        CHOICE=$(menu_box)
        if [ $? -ne 0 ]; then exit 0; fi 
        case $CHOICE in
            1) start_game ;;
            2) show_leaderboard ;;
            3) show_help ;;
            4) msg_box "關於" "SysAdmin Hero v5.0 (Ultimate)\n\n系統管理員模擬器\n涵蓋檔案、權限、網路、備份等 10 大領域。" ;;
            5) clear; echo "Bye!"; rm -rf "$GAME_DIR"; exit 0 ;;
        esac
    done
}

main_menu