#!/bin/bash


echo "--- 🐍 Pythonスクリプト実行開始 ---"
echo "   🗺️  マップ: $MAP_NAME"
echo "   ☀️  天候: $START_WEATHER"
echo "   💾  保存先: $OUTPUT_DIR"
echo "   🚗  車両数: $NUM_VEHICLES"
echo "   🚶  歩行者数: $NUM_WALKERS"
echo "-----------------------------------"
source ../env/bin/activate
# 渡された環境変数をそのまま引数としてpythonスクリプトを実行
python main.py \
    --map="$MAP_NAME" \
    --start-weather="$START_WEATHER" \
    --end-weather="$END_WEATHER" \
    --number-of-ego-vehicles=$NUM_EGO_VEHICLES \
    -n=$NUM_VEHICLES \
    -w=$NUM_WALKERS \
    --sync \
    --delta-seconds=$DELTA_SECONDS \
    --timeout=$TIMEOUT \
    --ignore-first-n-ticks=$IGNORE_TICKS \
    --duration=$DURATION \
    --output-dir="$OUTPUT_DIR" \
    -a # ユーザー指定の -a オプション

# Pythonスクリプトの終了コードを取得
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "--- ✅ Pythonスクリプト正常終了 ---"
else
    echo "--- ❌ Pythonスクリプトエラー (終了コード: $EXIT_CODE) ---"
fi

deactivate

# 終了コードを親スクリプトに返す
exit $EXIT_CODE