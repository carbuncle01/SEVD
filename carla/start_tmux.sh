#!/bin/bash


# tmux セッション名
SESSION_NAME="carla_data"

# セッションが既に存在するか確認
tmux has-session -t $SESSION_NAME 2>/dev/null

if [ $? -eq 0 ]; then
    echo "❌ エラー: tmux セッション '$SESSION_NAME' は既に存在します。"
    echo "   停止する場合: tmux kill-session -t $SESSION_NAME"
    echo "   アタッチする場合: tmux attach -t $SESSION_NAME"
    exit 1
fi

echo "🚀 tmux セッション '$SESSION_NAME' を作成します..."

# 1. デタッチ状態で新しいセッションを作成 (-d)
#    -s: セッション名, -n: 最初のウィンドウ名
tmux new-session -d -s $SESSION_NAME -n "CARLA_Run"

# 2. ウィンドウを左右に分割 (-h = horizontal split)
#    -t $SESSION_NAME:0  -> セッション名:ウィンドウ番号 をターゲットにする
tmux split-window -h -t $SESSION_NAME:0

# これで 0.0 (左) と 0.1 (右) の2つのペインができた

# 3. 左ペイン (0.0) に待機メッセージを表示
SERVER_PANE="$SESSION_NAME:0.0"
tmux send-keys -t $SERVER_PANE "echo '--- CARLA サーバーペイン ---'" C-m
tmux send-keys -t $SERVER_PANE "echo '制御スクリプトからの起動を待機します...'" C-m

# 4. 右ペイン (0.1) で制御スクリプトを実行
API_PANE="$SESSION_NAME:0.1"
CMD="bash ./run_all_sequences.sh --server-pane $SERVER_PANE"

# start_tmux.sh に渡された引数($@)をループ処理
for arg in "$@"; do
    CMD+=" $(printf "%q" "$arg")"
done

# 構築したコマンド全体を tmux に送信
tmux send-keys -t $API_PANE "$CMD" C-m

echo "✅ セッション '$SESSION_NAME' がバックグラウンドで起動しました。"
echo ""
echo "以下のコマンドでセッションにアタッチ（接続）してください："
echo "   tmux attach -t $SESSION_NAME"
echo ""