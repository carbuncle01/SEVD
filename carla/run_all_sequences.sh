#!/bin/bash
#
# 親スクリプト: run_all_sequences.sh
# ---------------------------------
# tmux の右ペインで実行され、左ペインのサーバーを制御する。
#

# =================================================================
# 設定セクション
# =================================================================
DEFAULT_BASE_DIR="dataset"
CARLA_SCRIPT="./../../CARLA_0.9.16/CARLA_0.9.16/CarlaUE4.sh" 
SERVER_WAIT_TIME=60 
PID_FILE="/tmp/carla_server.pid" 

export NUM_EGO_VEHICLES=1
export NUM_VEHICLES=120
export NUM_WALKERS=70
export FREQUENCY_HZ=30
export IGNORE_TICKS=35
export DURATION=18000
export TIMEOUT=60


# "Town11" "Town12" "Town13" はSpawnWalker関連のエラーが確認された
MAPS=(
    "Town01_Opt" "Town02_Opt" "Town03_Opt" "Town04_Opt"
    "Town05_Opt" "Town06_Opt" "Town07_Opt" "Town10HD_Opt"
    "Town15"
)
GOOD_WEATHERS=(
    "ClearNoon" "CloudyNoon" "SoftRainNoon"
    "ClearSunset" "CloudySunset" "SoftRainSunset"
)
export DELTA_SECONDS=$(echo "scale=4; 1 / $FREQUENCY_HZ" | bc)
SIM_TIME_MIN=$(echo "scale=2; $DURATION / $FREQUENCY_HZ / 60" | bc)
NUM_MAPS=${#MAPS[@]}
NUM_WEATHERS=${#GOOD_WEATHERS[@]}
TOTAL_RUNS=$(($NUM_MAPS * $NUM_WEATHERS))

# =================================================================
# 引数解析セクション
# =================================================================
START_INDEX=1
END_INDEX=$TOTAL_RUNS
BASE_DIR=$DEFAULT_BASE_DIR
SERVER_PANE="" 

ARGS_FOR_GETOPTS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --server-pane)
            SERVER_PANE="$2"
            shift 2
            ;;
        *)
            ARGS_FOR_GETOPTS+=("$1")
            shift
            ;;
    esac
done

set -- "${ARGS_FOR_GETOPTS[@]}"

usage() {
    echo "Usage: $0 (called from start_tmux.sh) [-b BASE_DIR] [-s START_INDEX] [-e END_INDEX]"
    echo "  --server-pane <pane_id> は start_tmux.sh から自動で渡されます。"
    exit 1
}

while getopts "b:s:e:h" opt; do
    case ${opt} in
        b) BASE_DIR=$OPTARG ;;
        s) START_INDEX=$OPTARG ;;
        e) END_INDEX=$OPTARG ;;
        h) usage ;;
        \?) usage ;;
    esac
done

if [ -z "$SERVER_PANE" ]; then
    echo "❌ エラー: --server-pane が指定されていません。"
    echo "   このスクリプトは 'start_tmux.sh' から実行してください。"
    exit 1
fi

# 今回の実行回数を計算
THIS_TOTAL_RUNS=$((END_INDEX - START_INDEX + 1))
CURRENT_STEP=0

# =================================================================
# 実行セクション
# =================================================================
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
RUN_BASE_DIR="${BASE_DIR}/${TIMESTAMP}_${START_INDEX}_${END_INDEX}"
mkdir -p "$RUN_BASE_DIR"

echo "================================================="
echo " CARLA 制御ループ (tmux) を開始します"
echo "   (このペインでAPI実行、左ペイン ($SERVER_PANE) でサーバー実行)"
echo "================================================="
echo "📂 ベースディレクトリ: $RUN_BASE_DIR"
echo "🎯 実行範囲: $START_INDEX から $END_INDEX まで (計 $THIS_TOTAL_RUNS 件)"
echo "================================================="
echo ""

for (( CURRENT_RUN=START_INDEX; CURRENT_RUN<=END_INDEX; CURRENT_RUN++ ))
do
    CURRENT_STEP=$((CURRENT_STEP + 1))

    # --- 1. パラメータの特定 ---
    IDX=$((CURRENT_RUN - 1))
    MAP_IDX=$((IDX / NUM_WEATHERS))
    WEATHER_IDX=$((IDX % NUM_WEATHERS))
    
    export MAP_NAME=${MAPS[$MAP_IDX]}
    export START_WEATHER=${GOOD_WEATHERS[$WEATHER_IDX]}
    export END_WEATHER=${GOOD_WEATHERS[$WEATHER_IDX]}
    
    RUN_ID_PADDED=$(printf "%03d" $CURRENT_RUN)
    export OUTPUT_DIR="${RUN_BASE_DIR}/${RUN_ID_PADDED}_${MAP_NAME}_${START_WEATHER}"
    mkdir -p "$OUTPUT_DIR"

    echo "================================================="
    echo "🔄 実行中 (シーケンス $CURRENT_RUN / 全体 $TOTAL_RUNS) --- [今回の $CURRENT_STEP / $THIS_TOTAL_RUNS 件目]"
    echo "================================================="
    echo "   💾 保存先: $OUTPUT_DIR"
    echo ""
    
    # --- 2. Terminal 1 (左ペイン): CARLAサーバーを起動 ---
    echo "🚀 CARLAサーバーを $SERVER_PANE で起動します..."
    
    tmux send-keys -t "$SERVER_PANE" \
        "rm -f $PID_FILE; bash $CARLA_SCRIPT -RenderOffScreen & echo \$! > $PID_FILE" C-m

    echo "   起動待機中... ($SERVER_WAIT_TIME 秒)"
    sleep $SERVER_WAIT_TIME

    if [ ! -f "$PID_FILE" ]; then
        echo "❌ サーバーPIDファイル ($PID_FILE) が見つかりません。起動失敗。"
        tmux send-keys -t "$SERVER_PANE" "echo '!! 起動に失敗したようです !!'" C-m
        continue
    fi
    
    SERVER_PID=$(cat $PID_FILE)
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "❌ サーバー(PID: $SERVER_PID) が起動していません。スキップします。"
        tmux send-keys -t "$SERVER_PANE" "echo '!! プロセス(PID: $SERVER_PID) が見つかりません !!'" C-m
        continue
    fi
    echo "   サーバー起動完了 (PID: $SERVER_PID)"
    echo ""

    # --- 3. Terminal 2 (右ペイン): データ収集スクリプト (子) を実行 ---
    bash ./run_sequence.sh
    COLLECT_EXIT_CODE=$?

    echo ""
    if [ $COLLECT_EXIT_CODE -eq 0 ]; then
        echo "✅ データ収集 完了 ($CURRENT_STEP / $THIS_TOTAL_RUNS 件目)"
    else
        echo "❌ データ収集 エラー ($CURRENT_STEP / $THIS_TOTAL_RUNS 件目)"
        touch "${OUTPUT_DIR}/_ERROR"
    fi
    echo ""

    # --- 4. Terminal 1 (左ペイン): CARLAサーバーを停止 ---
    echo "🛑 CARLAサーバー (PID: $SERVER_PID) を停止します..."
    if kill -0 $SERVER_PID 2>/dev/null; then
        kill $SERVER_PID
        
        echo "   (終了待機中... 5秒)"
        sleep 5 
        if kill -0 $SERVER_PID 2>/dev/null; then
            echo "   プロセスが終了しません。強制終了 (kill -9) します。"
            kill -9 $SERVER_PID
            sleep 2 
        else
            echo "   プロセスは正常に終了しました。"
        fi
        
        tmux send-keys -t "$SERVER_PANE" "echo 'サーバー(PID: $SERVER_PID) は停止しました。'" C-m
    else
        echo "   サーバー(PID: $SERVER_PID) は既に停止していました。"
    fi
    
    echo "   CARLAポート (2000-2002) をクリーンアップします..."
    if command -v fuser &> /dev/null; then
        fuser -k -n tcp 2000 2>/dev/null
        fuser -k -n tcp 2001 2>/dev/null
        fuser -k -n tcp 2002 2>/dev/null
    else
        echo "   (警告: 'fuser' コマンドが見つかりません。)"
        echo "   (推奨: sudo apt install psmisc)"
    fi
    
    echo "   サーバー停止・クリーンアップ完了。"
    echo ""
    echo "-------------------------------------------------"
done

echo "================================================="
echo "✅✅ 指定範囲の全ての処理が完了しました"
echo "================================================="
tmux send-keys -t "$SERVER_PANE" "echo '--- 全ての処理が完了しました ---'" C-m